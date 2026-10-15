#!/usr/bin/env python3
"""Gearforge string extractor.

Scans the Swift sources and GameData.json and returns every string the app looks up at runtime:

    {"ui":   [english keys...],            -> Localizable.strings (key = English text)
     "data": {key: english, ...}}          -> GameData.strings   (item.<id>, level.<L>.title, ...)

Sources (see docs/team/localization.md):
  * App/Sources/**/*.swift        string literals passed to SwiftUI initialisers that take a LocalizedStringKey
                                  (Text, Button, Toggle, Picker, ...), to L()/LF(), to show() and to the app's own
                                  helpers that localise their title (MenuButton, PanelChrome, row, itemsRow, ...),
                                  plus `var label: String { ... return "..." }` switches (EntityStatus labels).
  * Core/Sources/**/*.swift       PlacementError.message strings, .custom("...") errors, .alert("...") messages,
                                  `var label: String` switches (StatsWindow).
  * Core/.../GameData.json        content names.
  * Core/.../Levels.swift         campaign level + objective text.

Deterministic: output is sorted. Run directly to print counts; `--json` dumps the result, `--report` lists the
literals that need a code change before they can be localised.
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass, field

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP_SOURCES = os.path.join(ROOT, "App", "Sources")
CORE_SOURCES = os.path.join(ROOT, "Core", "Sources")
GAMEDATA_JSON = os.path.join(CORE_SOURCES, "FactoryCore", "Resources", "GameData.json")
LEVELS_SWIFT = os.path.join(CORE_SOURCES, "FactoryCore", "Progression", "Levels.swift")

# Call -> argument labels whose string literal is a localisation key. `None` = the first, unlabelled argument.
UI_CALLS: dict[str, set] = {
    # SwiftUI initialisers / modifiers taking a LocalizedStringKey
    "Text": {None}, "Button": {None}, "TextField": {None}, "SecureField": {None}, "Toggle": {None},
    "Picker": {None}, "Stepper": {None}, "Label": {None}, "Section": {None}, "Menu": {None}, "Link": {None},
    "navigationTitle": {None}, "alert": {None}, "confirmationDialog": {None}, "LocalizedStringKey": {None},
    # Gearforge lookups
    "L": {None}, "LF": {None}, "show": {None},
    # Gearforge helpers whose title goes through LocalizedStringKey(title) / L(title)
    "row": {None}, "prioPicker": {None}, "itemsRow": {None}, "column": {None}, "section": {None},
    "LoadingView": {"text"}, "MenuButton": {"title", "subtitle"}, "PanelChrome": {"title"}, "start": {"label"},
}
# Calls whose literal is formatted by us (L/LF/show/start) — interpolation there can never match a key.
EXPLICIT_CALLS = {"L", "LF", "show", "start", "LoadingView", "MenuButton", "PanelChrome", "row", "prioPicker",
                  "itemsRow", "column", "section"}

# SwiftUI turns `Text("Max (\(n))")` into the key "Max (%lld)". Interpolated expressions whose type we know,
# so those keys can be translated today (they are still listed under "needs code change": prefer LF()).
SWIFTUI_INTERP_SPECIFIERS = {
    "n": "%lld",
    "model.settings.autosaveSlots": "%lld",
    'inv.bar.map(String.init) ?? "none"': "%@",
}

ASSET_PREFIXES = ("ui_", "i_", "e_", "f_", "tile_", "ore_", "char_", "status_", "belt_", "ins_", "pipe_")
LETTER = re.compile(r"[^\W\d_]", re.UNICODE)
ID_LIKE = re.compile(r"^[a-z0-9_.\-]+$")
FILE_LIKE = re.compile(r"^[\w\-]+\.(json|png|swift|strings|plist|txt|bin|gfsave)$")
IDENT_BEFORE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*$")
LABEL_PREFIX = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", re.S)
FORMAT_LETTERS = re.compile(r"%(\d+\$)?[-+ 0#]*\d*(\.\d+)?(lld|ld|d|i|u|f|e|g|s|@|x)")


# --------------------------------------------------------------------------------------------- Swift lexer

@dataclass
class Literal:
    value: str            # unescaped text; interpolations kept as raw "\(expr)"
    raw: str              # literal as written (without quotes)
    interps: list         # raw interpolation expressions
    file: str
    line: int
    callee: str | None = None
    arg_index: int = 0
    prefix: str = ""
    suffix: str | None = None


@dataclass
class Frame:
    ch: str
    callee: str | None
    arg_start: int
    arg_index: int = 0
    pending: list = field(default_factory=list)


_ESC = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


def _read_string(src: str, i: int) -> tuple[int, str, str, list]:
    """src[i] is the opening quote of a single-line literal. Returns (end, value, raw, interps)."""
    j = i + 1
    out: list[str] = []
    interps: list[str] = []
    while j < len(src):
        c = src[j]
        if c == '"':
            return j + 1, "".join(out), src[i + 1:j], interps
        if c == "\\":
            n = src[j + 1]
            if n == "(":
                k = _skip_interp(src, j + 2)
                expr = src[j + 2:k - 1]
                interps.append(expr)
                out.append("\\(" + expr + ")")
                j = k
                continue
            if n == "u" and src[j + 2] == "{":
                k = src.index("}", j)
                out.append(chr(int(src[j + 3:k], 16)))
                j = k + 1
                continue
            out.append(_ESC.get(n, n))
            j += 2
            continue
        if c == "\n":
            break
        out.append(c)
        j += 1
    raise ValueError("unterminated string literal")


def _skip_interp(src: str, j: int) -> int:
    """j is just after '\\('. Returns index after the matching ')'."""
    depth = 1
    while depth:
        c = src[j]
        if c == '"':
            j = _read_string(src, j)[0]
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        j += 1
    return j


def scan_swift(path: str) -> list[Literal]:
    """All single-line string literals of a Swift file, with their call context."""
    src = open(path, encoding="utf-8").read()
    rel = os.path.relpath(path, ROOT)
    lits: list[Literal] = []
    stack: list[Frame] = [Frame("", None, 0)]
    i, n = 0, len(src)

    def close_arg(fr: Frame, end: int) -> None:
        for lit, lit_end in fr.pending:
            lit.suffix = src[lit_end:end].strip()
        fr.pending.clear()

    while i < n:
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
            continue
        if src.startswith("/*", i):
            depth, i = 1, i + 2
            while depth and i < n:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            continue
        if src.startswith('"""', i):
            i = src.index('"""', i + 3) + 3
            continue
        if c == "#" and src.startswith('#"', i):          # raw string: not used for UI text
            i = src.index('"#', i + 2) + 2
            continue
        if c == '"':
            end, value, raw, interps = _read_string(src, i)
            fr = stack[-1]
            lit = Literal(value, raw, interps, rel, src.count("\n", 0, i) + 1,
                          callee=fr.callee, arg_index=fr.arg_index, prefix=src[fr.arg_start:i].strip())
            # Parentheses without a callee (grouping) are transparent.
            k = len(stack) - 1
            while k > 0 and stack[k].ch == "(" and stack[k].callee is None:
                k -= 1
            if k != len(stack) - 1:
                outer = stack[k]
                lit.callee, lit.arg_index = outer.callee, outer.arg_index
                lit.prefix = src[outer.arg_start:i].strip()
            fr.pending.append((lit, end))
            lits.append(lit)
            i = end
            continue
        if c in "([{":
            callee = None
            if c == "(":
                m = IDENT_BEFORE.search(src, max(0, i - 80), i)
                if m and m.end() == i:
                    callee = m.group(1)
            stack.append(Frame(c, callee if c == "(" else None, i + 1))
            i += 1
            continue
        if c in ")]}":
            if len(stack) > 1:
                close_arg(stack.pop(), i)
            i += 1
            continue
        if c == "," and stack[-1].ch in "([":
            fr = stack[-1]
            close_arg(fr, i)
            fr.arg_index += 1
            fr.arg_start = i + 1
        i += 1
    close_arg(stack[0], n)
    return lits


def _is_text(value: str) -> bool:
    """True for strings that are human text (not ids, asset names, numbers, format-only strings)."""
    plain = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "", value)
    plain = FORMAT_LETTERS.sub("", plain)
    if not LETTER.search(plain):
        return False
    if value.startswith(ASSET_PREFIXES) or ID_LIKE.match(value) or FILE_LIKE.match(value):
        return False
    return True


def _key_position(lit: Literal) -> str | None:
    """Return the argument label the literal sits in if it is a key position, else None."""
    allowed = UI_CALLS.get(lit.callee or "")
    if allowed is None:
        return None
    label, rest = None, lit.prefix
    m = LABEL_PREFIX.match(rest)
    if m and "?" not in m.group(1):
        label, rest = m.group(1), m.group(2).strip()
    if label not in allowed:
        return None
    if label is None and lit.arg_index != 0:
        return None
    ternary = False
    if rest:
        if "?" in rest and rest[-1] in "?:":
            ternary = True
        else:
            return None
    suffix = lit.suffix or ""
    if suffix and not (ternary and suffix.startswith(":")) and not (suffix.startswith(":") and "?" in rest):
        return None
    return label or "_"


def _swift_files(root: str) -> list[str]:
    out = []
    for d, _, files in os.walk(root):
        out += [os.path.join(d, f) for f in files if f.endswith(".swift")]
    return sorted(out)


def _label_switch_literals(path: str, prop: str) -> list[str]:
    """`var <prop>: String { switch self { case ...: return "X" } }` -> ["X", ...]"""
    src = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"var\s+%s\s*:\s*String\s*\{" % prop, src):
        depth, j = 1, m.end()
        while depth:
            depth += {"{": 1, "}": -1}.get(src[j], 0)
            j += 1
        out += [_unescape(s) for s in re.findall(r'return\s+"((?:[^"\\]|\\.)*)"', src[m.end():j])]
    return out


def _unescape(s: str) -> str:
    return re.sub(r"\\(.)", lambda m: _ESC.get(m.group(1), m.group(1)), s)


def _swiftui_interp_key(raw: str, interps: list, specs: list) -> str:
    """The key SwiftUI's LocalizedStringKey builds: literal parts with % doubled, interpolations -> specifiers."""
    out, rest = [], raw
    for expr, spec in zip(interps, specs):
        head, rest = rest.split("\\(" + expr + ")", 1)
        out += [_unescape(head).replace("%", "%%"), spec]
    out.append(_unescape(rest).replace("%", "%%"))
    return "".join(out)


# --------------------------------------------------------------------------------------------- UI keys

def extract_ui() -> tuple[set, list]:
    """Returns (keys, needs_code_change) where needs_code_change is a list of (file, line, text, reason)."""
    keys: set[str] = set()
    issues: list[tuple] = []

    for path in _swift_files(APP_SOURCES):
        if path.endswith("Localization.swift"):
            continue
        for lit in scan_swift(path):
            if not _is_text(lit.value):
                continue
            # String(format: "Speed %.2f", ...) shown to the player is never looked up.
            if lit.callee == "String" and lit.prefix.startswith("format:"):
                issues.append((lit.file, lit.line, lit.raw, "String(format:) with words — use LF() with a %@ key"))
                continue
            pos = _key_position(lit)
            if pos is None:
                continue
            if lit.interps:
                if lit.callee in EXPLICIT_CALLS:
                    issues.append((lit.file, lit.line, lit.raw,
                                   "interpolated string passed as a key — use LF(\"… %@ …\", value)"))
                    continue
                spec = [SWIFTUI_INTERP_SPECIFIERS.get(e) for e in lit.interps]
                issues.append((lit.file, lit.line, lit.raw, "SwiftUI interpolated literal — prefer LF() with %@"))
                if all(spec):
                    keys.add(_swiftui_interp_key(lit.raw, lit.interps, spec))
                continue
            keys.add(lit.value)
        for lbl in _label_switch_literals(path, "label"):
            if LETTER.search(lbl):
                keys.add(lbl)

    for path in _swift_files(CORE_SOURCES):
        src_lits = scan_swift(path)
        for lit in src_lits:
            if lit.callee in ("custom", "alert") and lit.arg_index == 0 and not lit.prefix and _is_text(lit.value):
                if lit.interps:
                    issues.append((lit.file, lit.line, lit.raw,
                                   "Core .%s() message built by interpolation — cannot match a key" % lit.callee))
                else:
                    keys.add(lit.value)
        for prop in ("message", "label"):
            for s in _label_switch_literals(path, prop):
                if LETTER.search(s):
                    keys.add(s)
    issues.sort()
    # Plain L("…") anywhere (also nested inside other calls, e.g. LF("Limit: %@", x ?? L("none"))).
    for path in _swift_files(APP_SOURCES):
        if path.endswith("Localization.swift"):
            continue
        for m in re.finditer(r'(?<![A-Za-z0-9_])L\("((?:[^"\\]|\\.)*)"\)', open(path, encoding="utf-8").read()):
            if "\\(" not in m.group(1):
                keys.add(_unescape(m.group(1)))
    # Guided tutorial texts (Core): h("English text", …) in Progression/Tutorial.swift.
    tut = os.path.join(CORE_SOURCES, "FactoryCore", "Progression", "Tutorial.swift")
    if os.path.exists(tut):
        for m in re.finditer(r'(?<![A-Za-z0-9_])h\(\s*"((?:[^"\\]|\\.)*)"', open(tut, encoding="utf-8").read()):
            if "\\(" not in m.group(1):
                keys.add(_unescape(m.group(1)))
    # FitPicker("Title", selection: …, options: [("Label", value), …]) — title and every tuple label are keys.
    for path in _swift_files(APP_SOURCES):
        src = open(path, encoding="utf-8").read()
        for m in re.finditer(r'(?<![A-Za-z0-9_])FitPicker\(', src):
            depth, i = 1, m.end()
            while i < len(src) and depth:
                c = src[i]
                if c == '"':
                    i += 1
                    while i < len(src) and src[i] != '"':
                        i += 2 if src[i] == "\\" else 1
                elif c in "([":
                    depth += 1
                elif c in ")]":
                    depth -= 1
                i += 1
            call = src[m.end():i]
            first = re.match(r'\s*' + STR, call)
            labels = ([first.group(1)] if first else []) + re.findall(r'\(\s*' + STR + r'\s*,', call)
            for lab in labels:
                if "\\(" not in lab and LETTER.search(lab):
                    keys.add(_unescape(lab))
    return keys, issues


# --------------------------------------------------------------------------------------------- data keys

STR = r'"((?:[^"\\]|\\.)*)"'
DATA_ARRAYS = [("items", "item"), ("entities", "entity"), ("recipes", "recipe"), ("technologies", "tech"),
               ("fluids", "fluid"), ("itemGroups", "group"), ("tiles", "tile"), ("resources", "resource")]


def extract_data() -> dict:
    data: dict[str, str] = {}
    gd = json.load(open(GAMEDATA_JSON, encoding="utf-8"))
    for arr, prefix in DATA_ARRAYS:
        for e in gd.get(arr, []):
            data["%s.%s" % (prefix, e["id"])] = e["name"]

    src = open(LEVELS_SWIFT, encoding="utf-8").read()
    heads = list(re.finditer(r"LevelDefinition\(\s*id:\s*%s,\s*title:\s*%s,\s*subtitle:\s*%s,\s*teaches:\s*%s"
                             % (STR, STR, STR, STR), src))
    if len(heads) != 8:
        raise SystemExit("extract: expected 8 LevelDefinition blocks in Levels.swift, found %d" % len(heads))
    for idx, m in enumerate(heads):
        lid = m.group(1)
        data["level.%s.title" % lid] = _unescape(m.group(2))
        data["level.%s.subtitle" % lid] = _unescape(m.group(3))
        data["level.%s.teaches" % lid] = _unescape(m.group(4))
        body = src[m.end(): heads[idx + 1].start() if idx + 1 < len(heads) else len(src)]
        objs = re.findall(r"\bo\((\d+),\s*%s,\s*\.\w+\([^)]*\)\s*(?:,\s*%s)?\s*\)" % (STR, STR), body)
        if not objs:
            raise SystemExit("extract: no objectives parsed for %s" % lid)
        for num, title, hint in objs:
            data["objective.%s.%s.title" % (lid, num)] = _unescape(title)
            if hint:
                data["objective.%s.%s.hint" % (lid, num)] = _unescape(hint)
    return dict(sorted(data.items()))


def extract() -> dict:
    ui, _ = extract_ui()
    return {"ui": sorted(ui), "data": extract_data()}


def needs_code_change() -> list:
    return extract_ui()[1]


def main(argv: list[str]) -> int:
    res = extract()
    if "--json" in argv:
        json.dump(res, sys.stdout, ensure_ascii=False, indent=1)
        print()
        return 0
    data = res["data"]
    by_prefix: dict[str, int] = {}
    for k in data:
        by_prefix[k.split(".")[0]] = by_prefix.get(k.split(".")[0], 0) + 1
    print("UI keys:   %d" % len(res["ui"]))
    print("Data keys: %d  (%s)" % (len(data), ", ".join("%s %d" % kv for kv in sorted(by_prefix.items()))))
    if "--report" in argv:
        print("\nNeeds code change:")
        for f, line, text, why in needs_code_change():
            print("  %s:%d  \"%s\"  — %s" % (f, line, text, why))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
