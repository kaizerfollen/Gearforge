#!/usr/bin/env python3
"""Validate an Xcode project.pbxproj (old-style / OpenStep ASCII plist) without Xcode.

Checks:
  1. Syntax: a full recursive-descent parse of the OpenStep plist grammar Xcode uses (dicts, arrays, quoted and
     unquoted strings, /* */ and // comments). Any unbalanced brace/paren, missing ';' or ',' or '=' fails.
  2. Top level: archiveVersion, objectVersion, objects, rootObject present; rootObject is a PBXProject.
  3. Every object has an `isa` and every object id is a 24-char uppercase hex id.
  4. Cross references: every value (anywhere in an object) that looks like an object id must exist in `objects`;
     known reference keys (fileRef, productRef, buildConfigurationList, children, files, ...) are type-checked
     against the isa they must point to.
  5. Reachability: every object is reachable from rootObject (no orphans), and every PBXBuildFile is listed in
     exactly one build phase.
  6. Per-isa required keys for the isas the Gearforge generator emits.

Usage: pbxproj_validate.py path/to/project.pbxproj   (exit status 0 = valid)
Importable: `validate(text) -> list[str]` returns the list of errors (empty = valid), `parse(text)` returns dicts.
"""
from __future__ import annotations

import re
import sys

ID_RE = re.compile(r"^[0-9A-F]{24}$")
UNQUOTED_CHARS = re.compile(r"[A-Za-z0-9_$/:.\-+]")


class ParseError(Exception):
    pass


class _Parser:
    def __init__(self, text: str):
        self.s = text
        self.i = 0
        self.n = len(text)

    def error(self, msg: str) -> ParseError:
        line = self.s.count("\n", 0, self.i) + 1
        col = self.i - (self.s.rfind("\n", 0, self.i) + 1) + 1
        return ParseError(f"line {line}, col {col}: {msg}")

    def skip(self) -> None:
        s, n = self.s, self.n
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("/*", self.i):
                j = s.find("*/", self.i + 2)
                if j < 0:
                    raise self.error("unterminated /* comment")
                self.i = j + 2
            elif s.startswith("//", self.i):
                j = s.find("\n", self.i)
                self.i = n if j < 0 else j + 1
            else:
                break

    def expect(self, ch: str) -> None:
        self.skip()
        if self.i >= self.n or self.s[self.i] != ch:
            got = self.s[self.i] if self.i < self.n else "EOF"
            raise self.error(f"expected '{ch}', got '{got}'")
        self.i += 1

    def peek(self) -> str:
        self.skip()
        return self.s[self.i] if self.i < self.n else ""

    def value(self):
        c = self.peek()
        if c == "{":
            return self.dict()
        if c == "(":
            return self.array()
        if c == '"':
            return self.quoted()
        if c and UNQUOTED_CHARS.match(c):
            return self.unquoted()
        raise self.error(f"unexpected character '{c or 'EOF'}'")

    def dict(self) -> dict:
        self.expect("{")
        d: dict = {}
        while True:
            c = self.peek()
            if c == "}":
                self.i += 1
                return d
            if not c:
                raise self.error("unterminated dictionary")
            k = self.value()
            if not isinstance(k, str):
                raise self.error("dictionary key must be a string")
            self.expect("=")
            v = self.value()
            self.expect(";")
            if k in d:
                raise self.error(f"duplicate key '{k}'")
            d[k] = v

    def array(self) -> list:
        self.expect("(")
        a: list = []
        while True:
            c = self.peek()
            if c == ")":
                self.i += 1
                return a
            if not c:
                raise self.error("unterminated array")
            a.append(self.value())
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c != ")":
                raise self.error(f"expected ',' or ')' in array, got '{c or 'EOF'}'")

    def quoted(self) -> str:
        self.expect('"')
        out = []
        s = self.s
        while True:
            if self.i >= self.n:
                raise self.error("unterminated string")
            c = s[self.i]
            if c == '"':
                self.i += 1
                return "".join(out)
            if c == "\\":
                self.i += 1
                if self.i >= self.n:
                    raise self.error("bad escape at EOF")
                e = s[self.i]
                out.append({"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'"}.get(e, e))
                self.i += 1
            else:
                out.append(c)
                self.i += 1

    def unquoted(self) -> str:
        j = self.i
        while j < self.n and UNQUOTED_CHARS.match(self.s[j]):
            j += 1
        tok = self.s[self.i:j]
        self.i = j
        return tok


def parse(text: str) -> dict:
    if not text.startswith("// !$*UTF8*$!"):
        raise ParseError("missing '// !$*UTF8*$!' header")
    p = _Parser(text)
    root = p.value()
    p.skip()
    if p.i != p.n:
        raise p.error("trailing content after root dictionary")
    if not isinstance(root, dict):
        raise ParseError("root is not a dictionary")
    return root


# key -> allowed isa(s) of the referenced object(s)
REF_KEYS = {
    "fileRef": {"PBXFileReference", "PBXGroup", "PBXVariantGroup", "XCVersionGroup"},
    "productRef": {"XCSwiftPackageProductDependency"},
    "package": {"XCLocalSwiftPackageReference", "XCRemoteSwiftPackageReference"},
    "buildConfigurationList": {"XCConfigurationList"},
    "buildConfigurations": {"XCBuildConfiguration"},
    "buildPhases": {"PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase",
                    "PBXCopyFilesBuildPhase", "PBXShellScriptBuildPhase", "PBXHeadersBuildPhase"},
    "files": {"PBXBuildFile"},
    "children": {"PBXFileReference", "PBXGroup", "PBXVariantGroup", "XCVersionGroup"},
    "mainGroup": {"PBXGroup"},
    "productRefGroup": {"PBXGroup"},
    "productReference": {"PBXFileReference"},
    "targets": {"PBXNativeTarget", "PBXAggregateTarget", "PBXLegacyTarget"},
    "packageReferences": {"XCLocalSwiftPackageReference", "XCRemoteSwiftPackageReference"},
    "packageProductDependencies": {"XCSwiftPackageProductDependency"},
    "dependencies": {"PBXTargetDependency"},
    "rootObject": {"PBXProject"},
}

REQUIRED = {
    "PBXProject": ["attributes", "buildConfigurationList", "compatibilityVersion", "mainGroup", "targets",
                   "projectDirPath", "projectRoot", "productRefGroup"],
    "PBXNativeTarget": ["buildConfigurationList", "buildPhases", "name", "productName", "productReference",
                        "productType"],
    "PBXFileReference": ["path", "sourceTree"],
    "PBXGroup": ["children", "sourceTree"],
    "PBXBuildFile": [],
    "XCBuildConfiguration": ["buildSettings", "name"],
    "XCConfigurationList": ["buildConfigurations", "defaultConfigurationName"],
    "PBXSourcesBuildPhase": ["buildActionMask", "files", "runOnlyForDeploymentPostprocessing"],
    "PBXFrameworksBuildPhase": ["buildActionMask", "files", "runOnlyForDeploymentPostprocessing"],
    "PBXResourcesBuildPhase": ["buildActionMask", "files", "runOnlyForDeploymentPostprocessing"],
    "XCLocalSwiftPackageReference": ["relativePath"],
    "XCSwiftPackageProductDependency": ["productName"],
}


def _walk_ids(v, out: list):
    if isinstance(v, str):
        if ID_RE.match(v):
            out.append(v)
    elif isinstance(v, list):
        for x in v:
            _walk_ids(x, out)
    elif isinstance(v, dict):
        for k, x in v.items():
            _walk_ids(k, out)
            _walk_ids(x, out)


def validate(text: str) -> list[str]:
    errors: list[str] = []
    try:
        root = parse(text)
    except ParseError as e:
        return [f"syntax: {e}"]

    for k in ("archiveVersion", "objectVersion", "objects", "rootObject"):
        if k not in root:
            errors.append(f"top level: missing '{k}'")
    if errors:
        return errors
    objs = root["objects"]
    if not isinstance(objs, dict):
        return ["top level: 'objects' is not a dictionary"]

    for oid, o in objs.items():
        if not ID_RE.match(oid):
            errors.append(f"object id '{oid}' is not 24 uppercase hex chars")
        if not isinstance(o, dict) or "isa" not in o:
            errors.append(f"{oid}: missing isa")
            continue
        for req in REQUIRED.get(o["isa"], []):
            if req not in o:
                errors.append(f"{oid} ({o['isa']}): missing required key '{req}'")
        if o["isa"] == "PBXBuildFile" and ("fileRef" in o) == ("productRef" in o):
            errors.append(f"{oid} (PBXBuildFile): needs exactly one of fileRef/productRef")
        # dangling references anywhere
        ids: list = []
        _walk_ids({k: v for k, v in o.items()}, ids)
        for rid in ids:
            if rid not in objs:
                errors.append(f"{oid} ({o['isa']}): dangling reference {rid}")
        # typed references
        for key, allowed in REF_KEYS.items():
            if key not in o:
                continue
            refs = o[key] if isinstance(o[key], list) else [o[key]]
            for r in refs:
                tgt = objs.get(r)
                if isinstance(tgt, dict) and tgt.get("isa") not in allowed:
                    errors.append(f"{oid} ({o['isa']}).{key} -> {r} is {tgt.get('isa')}, expected {sorted(allowed)}")

    rid = root["rootObject"]
    if not isinstance(objs.get(rid), dict) or objs[rid].get("isa") != "PBXProject":
        errors.append(f"rootObject {rid} is not a PBXProject")
        return errors

    # reachability
    seen = set()
    stack = [rid]
    while stack:
        cur = stack.pop()
        if cur in seen or cur not in objs:
            continue
        seen.add(cur)
        ids = []
        _walk_ids(objs[cur], ids)
        stack.extend(i for i in ids if i not in seen)
    for oid in objs:
        if oid not in seen:
            errors.append(f"{oid} ({objs[oid].get('isa')}): orphan (unreachable from rootObject)")

    # each PBXBuildFile in exactly one phase
    count = {oid: 0 for oid, o in objs.items() if isinstance(o, dict) and o.get("isa") == "PBXBuildFile"}
    for o in objs.values():
        if isinstance(o, dict) and o.get("isa", "").endswith("BuildPhase"):
            for f in o.get("files", []):
                if f in count:
                    count[f] += 1
    for oid, c in count.items():
        if c != 1:
            errors.append(f"{oid} (PBXBuildFile): listed in {c} build phases (expected 1)")

    # group children must not be listed twice
    parent = {}
    for oid, o in objs.items():
        if isinstance(o, dict) and o.get("isa") == "PBXGroup":
            for ch in o.get("children", []):
                if ch in parent:
                    errors.append(f"{ch}: child of two groups ({parent[ch]}, {oid})")
                parent[ch] = oid
    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        text = f.read()
    errs = validate(text)
    if errs:
        for e in errs:
            print(f"error: {e}")
        print(f"{argv[1]}: INVALID ({len(errs)} error(s))")
        return 1
    root = parse(text)
    print(f"{argv[1]}: OK ({len(root['objects'])} objects)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
