#!/usr/bin/env python3
"""Generate App/Gearforge.xcodeproj without Xcode or XcodeGen.

Writes:
  App/Gearforge.xcodeproj/project.pbxproj
  App/Gearforge.xcodeproj/xcshareddata/xcschemes/Gearforge.xcscheme

Inputs scanned at generation time (relative to App/):
  Sources/**.swift                 -> Sources build phase; groups mirror the folders
  Resources/*.atlas                -> folder reference, lastKnownFileType folder.skatlas (Xcode compiles a texture atlas)
  Resources/*.xcassets             -> asset catalog (Assets.xcassets + empty AppIcon set are created if missing)
  Resources/Sounds                 -> folder reference (lastKnownFileType folder): copied as the bundle folder "Sounds"
  Resources/**.json (+ audio/font) -> Copy Bundle Resources; sub-folders become groups
  ../Core                          -> local Swift package (XCLocalSwiftPackageReference), product FactoryCore linked

Object ids are the first 24 hex chars of sha1(stable key), so the output is a pure function of the file tree:
re-running without changes rewrites byte-identical files (the script reports "unchanged").

Usage:  python3 tools/ios/gen_xcodeproj.py [--check]
  --check  do not write; exit 1 if the committed project differs from what would be generated (CI / checkpoint use)
The generated pbxproj is validated with tools/ios/pbxproj_validate.py before it is written.

This script is the source of truth for the Xcode project. Re-run it whenever Swift files or resources are added,
removed or moved (edits made in Xcode's project editor are overwritten by the next run).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
APP = os.path.join(REPO, "App")
PROJ_DIR = os.path.join(APP, "Gearforge.xcodeproj")

sys.path.insert(0, HERE)
import pbxproj_validate  # noqa: E402

TARGET = "Gearforge"
BUNDLE_ID = "com.gearforge.game"
DEPLOYMENT = "17.0"
PACKAGE_PATH = "../Core"
PACKAGE_PRODUCT = "FactoryCore"

# Resource sub-folders (relative to App/) added as folder references ("blue folders") instead of groups, so the
# bundle keeps the sub-folder: AudioManager loads Bundle.main.url(forResource:withExtension:subdirectory: "Sounds").
FOLDER_REFERENCES = {"Resources/Sounds"}

RESOURCE_TYPES = {
    ".json": "text.json",
    ".caf": "file", ".wav": "audio.wav", ".m4a": "file", ".mp3": "audio.mp3", ".aif": "audio.aiff",
    ".aiff": "audio.aiff", ".ttf": "file", ".otf": "file",
}
SKIP_NAMES = {".DS_Store", ".gitkeep"}


# ---------------------------------------------------------------------------------------------------------------
# ids + old-style plist serialisation

def oid(key: str) -> str:
    return hashlib.sha1(("gearforge-xcodeproj:" + key).encode("utf-8")).hexdigest()[:24].upper()


_UNQUOTED = re.compile(r"^[A-Za-z0-9_./]+$")


def q(s: str) -> str:
    """Quote a plist string the way Xcode does (bare only for [A-Za-z0-9_./])."""
    if _UNQUOTED.match(s):
        return s
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return f'"{s}"'


class Obj:
    """A pbxproj object: isa + ordered key/value pairs. Values: str, Ref, list, dict."""

    def __init__(self, key: str, isa: str, comment: str, **fields):
        self.id = oid(key)
        self.isa = isa
        self.comment = comment
        self.fields = fields


class Ref:
    def __init__(self, obj: Obj):
        self.obj = obj


def fmt_value(v, indent: int) -> str:
    tab = "\t" * indent
    if isinstance(v, Ref):
        return f"{v.obj.id} /* {v.obj.comment} */" if v.obj.comment else v.obj.id
    if isinstance(v, str):
        return q(v)
    if isinstance(v, list):
        if not v:
            return "(\n" + tab + ")"
        inner = "".join(f"{tab}\t{fmt_value(x, indent + 1)},\n" for x in v)
        return "(\n" + inner + tab + ")"
    if isinstance(v, dict):
        inner = "".join(f"{tab}\t{q(k)} = {fmt_value(x, indent + 1)};\n" for k, x in v.items())
        return "{\n" + inner + tab + "}"
    raise TypeError(type(v))


def fmt_inline(v) -> str:
    if isinstance(v, Ref):
        return f"{v.obj.id} /* {v.obj.comment} */"
    if isinstance(v, str):
        return q(v)
    raise TypeError("inline objects only hold scalars/refs")


INLINE_ISAS = {"PBXBuildFile", "PBXFileReference"}


def fmt_obj(o: Obj) -> str:
    head = f"\t\t{o.id} /* {o.comment} */ = " if o.comment else f"\t\t{o.id} = "
    if o.isa in INLINE_ISAS:
        body = " ".join([f"isa = {o.isa};"] + [f"{q(k)} = {fmt_inline(v)};" for k, v in o.fields.items()])
        return head + "{" + body + " };\n"
    lines = [f"\t\t\tisa = {o.isa};\n"]
    for k, v in o.fields.items():
        lines.append(f"\t\t\t{q(k)} = {fmt_value(v, 3)};\n")
    return head + "{\n" + "".join(lines) + "\t\t};\n"


def serialize(objects: list[Obj], root: Obj) -> str:
    by_isa: dict[str, list[Obj]] = {}
    for o in objects:
        by_isa.setdefault(o.isa, []).append(o)
    out = ["// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 60;\n\tobjects = {\n"]
    for isa in sorted(by_isa):
        out.append(f"\n/* Begin {isa} section */\n")
        for o in sorted(by_isa[isa], key=lambda x: x.id):
            out.append(fmt_obj(o))
        out.append(f"/* End {isa} section */\n")
    out.append(f"\t}};\n\trootObject = {root.id} /* Project object */;\n}}\n")
    return "".join(out)


# ---------------------------------------------------------------------------------------------------------------
# project model

def build_settings_project(config: str) -> dict:
    s = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
    }
    if config == "Debug":
        s.update({
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        })
    else:
        s.update({
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "VALIDATE_PRODUCT": "YES",
        })
    return dict(sorted(s.items()))


def build_settings_target(config: str) -> dict:
    orient = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
    s = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "Gearforge",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.games",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIRequiresFullScreen": "YES",
        "INFOPLIST_KEY_UIStatusBarHidden": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": orient,
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": orient,
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    if config == "Release":
        s["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
        s["SWIFT_COMPILATION_MODE"] = "wholemodule"
    else:
        s["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
    return dict(sorted(s.items()))


def ensure_asset_catalog() -> list[str]:
    """Create Resources/Assets.xcassets with an empty AppIcon set if missing (ASSETCATALOG_COMPILER_APPICON_NAME
    names it; actool errors when the set does not exist). Never touches an existing catalog's other contents."""
    base = os.path.join(APP, "Resources", "Assets.xcassets")
    info = {"author": "xcode", "version": 1}
    files = {
        "Contents.json": {"info": info},
        "AppIcon.appiconset/Contents.json": {
            "images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": info},
    }
    created = []
    for rel, content in files.items():
        p = os.path.join(base, rel)
        if not os.path.exists(p):
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                json.dump(content, f, indent=2)
                f.write("\n")
            created.append(os.path.relpath(p, REPO))
    return created


def listdir_sorted(path: str) -> list[str]:
    return sorted((n for n in os.listdir(path) if n not in SKIP_NAMES and not n.startswith(".")),
                  key=lambda n: n.lower())


class Model:
    def __init__(self):
        self.objects: list[Obj] = []
        self.sources: list[Obj] = []      # PBXBuildFile
        self.resources: list[Obj] = []    # PBXBuildFile
        self.regions: set[str] = set()    # languages found in *.lproj

    def add(self, o: Obj) -> Obj:
        self.objects.append(o)
        return o

    def file_ref(self, relpath: str, ftype: str) -> Obj:
        name = os.path.basename(relpath)
        return self.add(Obj("fileref:" + relpath, "PBXFileReference", name,
                            lastKnownFileType=ftype, path=name, sourceTree="<group>"))

    def build_file(self, ref: Obj, phase: str) -> Obj:
        bf = self.add(Obj(f"buildfile:{phase}:{ref.fields['path']}:{ref.id}", "PBXBuildFile",
                          f"{ref.comment} in {phase}", fileRef=Ref(ref)))
        (self.sources if phase == "Sources" else self.resources).append(bf)
        return bf

    def scan_sources(self, abs_dir: str, rel: str) -> Obj | None:
        """Group for a folder under Sources; None if it contains no Swift files."""
        groups, files = [], []
        for n in listdir_sorted(abs_dir):
            p = os.path.join(abs_dir, n)
            r = f"{rel}/{n}"
            if os.path.isdir(p):
                g = self.scan_sources(p, r)
                if g:
                    groups.append(g)
            elif n.endswith(".swift"):
                ref = self.file_ref(r, "sourcecode.swift")
                self.build_file(ref, "Sources")
                files.append(ref)
        if not groups and not files:
            return None
        name = os.path.basename(rel)
        return self.add(Obj("group:" + rel, "PBXGroup", name,
                            children=[Ref(x) for x in groups + files], path=name, sourceTree="<group>"))

    def scan_resources(self, abs_dir: str, rel: str) -> Obj | None:
        groups, files = [], []
        for n in listdir_sorted(abs_dir):
            p = os.path.join(abs_dir, n)
            r = f"{rel}/{n}"
            ext = os.path.splitext(n)[1].lower()
            if os.path.isdir(p) and ext == ".lproj":
                continue                                # handled below as variant groups
            if os.path.isdir(p) and ext == ".atlas":
                ref = self.file_ref(r, "folder.skatlas")
            elif os.path.isdir(p) and ext == ".xcassets":
                ref = self.file_ref(r, "folder.assetcatalog")
            elif os.path.isdir(p) and r in FOLDER_REFERENCES:
                ref = self.file_ref(r, "folder")         # blue folder: contents copied as a sub-folder of the bundle
            elif os.path.isdir(p):
                g = self.scan_resources(p, r)
                if g:
                    groups.append(g)
                continue
            elif ext in RESOURCE_TYPES:
                ref = self.file_ref(r, RESOURCE_TYPES[ext])
            else:
                continue
            self.build_file(ref, "Resources")
            files.append(ref)
        # Localized resources: <lang>.lproj/<name>.strings → one PBXVariantGroup per file name.
        lprojs = [n for n in listdir_sorted(abs_dir) if n.endswith(".lproj") and os.path.isdir(os.path.join(abs_dir, n))]
        names = sorted({f for l in lprojs for f in os.listdir(os.path.join(abs_dir, l)) if f.endswith(".strings")})
        for fname in names:
            children = []
            for l in lprojs:
                if os.path.exists(os.path.join(abs_dir, l, fname)):
                    lang = l[:-len(".lproj")]
                    self.regions.add(lang)
                    children.append(self.add(Obj(f"fileref:{rel}/{l}/{fname}", "PBXFileReference", lang,
                                                 lastKnownFileType="text.plist.strings", name=lang,
                                                 path=f"{l}/{fname}", sourceTree="<group>")))
            vg = self.add(Obj(f"variant:{rel}/{fname}", "PBXVariantGroup", fname,
                              children=[Ref(c) for c in children], name=fname, sourceTree="<group>"))
            bf = self.add(Obj(f"buildfile:Resources:{rel}/{fname}", "PBXBuildFile", f"{fname} in Resources", fileRef=Ref(vg)))
            self.resources.append(bf)
            files.append(vg)
        if not groups and not files:
            return None
        name = os.path.basename(rel)
        return self.add(Obj("group:" + rel, "PBXGroup", name,
                            children=[Ref(x) for x in groups + files], path=name, sourceTree="<group>"))


def generate() -> tuple[str, str, Obj]:
    m = Model()
    top_children = []
    src_dir = os.path.join(APP, "Sources")
    if os.path.isdir(src_dir):
        g = m.scan_sources(src_dir, "Sources")
        if g:
            top_children.append(g)
    res_dir = os.path.join(APP, "Resources")
    if os.path.isdir(res_dir):
        g = m.scan_resources(res_dir, "Resources")
        if g:
            top_children.append(g)

    product = m.add(Obj("product:app", "PBXFileReference", f"{TARGET}.app", explicitFileType="wrapper.application",
                        includeInIndex="0", path=f"{TARGET}.app", sourceTree="BUILT_PRODUCTS_DIR"))
    products_group = m.add(Obj("group:Products", "PBXGroup", "Products", children=[Ref(product)],
                               name="Products", sourceTree="<group>"))
    main_group = m.add(Obj("group:main", "PBXGroup", "", children=[Ref(x) for x in top_children] +
                           [Ref(products_group)], sourceTree="<group>"))

    pkg = m.add(Obj("package:core", "XCLocalSwiftPackageReference", f'XCLocalSwiftPackageReference "{PACKAGE_PATH}"',
                    relativePath=PACKAGE_PATH))
    pkg_product = m.add(Obj("package-product:" + PACKAGE_PRODUCT, "XCSwiftPackageProductDependency", PACKAGE_PRODUCT,
                            package=Ref(pkg), productName=PACKAGE_PRODUCT))
    fw_file = m.add(Obj("buildfile:Frameworks:" + PACKAGE_PRODUCT, "PBXBuildFile", f"{PACKAGE_PRODUCT} in Frameworks",
                        productRef=Ref(pkg_product)))

    def phase(isa: str, name: str, files: list[Obj]) -> Obj:
        return m.add(Obj("phase:" + name, isa, name, buildActionMask="2147483647",
                         files=[Ref(f) for f in sorted(files, key=lambda f: f.comment.lower())],
                         runOnlyForDeploymentPostprocessing="0"))

    sources_phase = phase("PBXSourcesBuildPhase", "Sources", m.sources)
    frameworks_phase = phase("PBXFrameworksBuildPhase", "Frameworks", [fw_file])
    resources_phase = phase("PBXResourcesBuildPhase", "Resources", m.resources)

    def config_list(scope: str, settings_fn, owner_comment: str) -> Obj:
        cfgs = [m.add(Obj(f"config:{scope}:{c}", "XCBuildConfiguration", c, buildSettings=settings_fn(c), name=c))
                for c in ("Debug", "Release")]
        return m.add(Obj(f"configlist:{scope}", "XCConfigurationList",
                         f'Build configuration list for {owner_comment}',
                         buildConfigurations=[Ref(c) for c in cfgs], defaultConfigurationIsVisible="0",
                         defaultConfigurationName="Release"))

    target_cfgs = config_list("target", build_settings_target, f'PBXNativeTarget "{TARGET}"')
    target = m.add(Obj("target:" + TARGET, "PBXNativeTarget", TARGET,
                       buildConfigurationList=Ref(target_cfgs),
                       buildPhases=[Ref(sources_phase), Ref(frameworks_phase), Ref(resources_phase)],
                       buildRules=[], dependencies=[], name=TARGET,
                       packageProductDependencies=[Ref(pkg_product)], productName=TARGET,
                       productReference=Ref(product), productType="com.apple.product-type.application"))
    project_cfgs = config_list("project", build_settings_project, f'PBXProject "{TARGET}"')
    project = m.add(Obj("project", "PBXProject", "Project object",
                        attributes={
                            "BuildIndependentTargetsInParallel": "1",
                            "LastSwiftUpdateCheck": "1500",
                            "LastUpgradeCheck": "1500",
                            "TargetAttributes": {target.id: {"CreatedOnToolsVersion": "15.0"}},
                        },
                        buildConfigurationList=Ref(project_cfgs), compatibilityVersion="Xcode 14.0",
                        developmentRegion="en", hasScannedForEncodings="0", knownRegions=["en", "Base"] + sorted(m.regions - {"en", "Base"}),
                        mainGroup=Ref(main_group), packageReferences=[Ref(pkg)],
                        productRefGroup=Ref(products_group), projectDirPath="", projectRoot="",
                        targets=[Ref(target)]))
    ids = [o.id for o in m.objects]
    if len(ids) != len(set(ids)):
        raise SystemExit("internal error: object id collision")
    return serialize(m.objects, project), scheme_xml(target.id), project


def scheme_xml(target_id: str) -> str:
    ref = f"""BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{TARGET}.app"
               BlueprintName = "{TARGET}"
               ReferencedContainer = "container:{TARGET}.xcodeproj">
            </BuildableReference>"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <{ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <{ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <{ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def write_if_changed(path: str, text: str) -> bool:
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return True


def main(argv: list[str]) -> int:
    check = "--check" in argv[1:]
    if not check:
        for c in ensure_asset_catalog():
            print(f"created {c}")
    pbx, scheme, _ = generate()
    errs = pbxproj_validate.validate(pbx, app_dir=APP)
    if errs:
        for e in errs:
            print(f"error: {e}")
        print("generated project failed validation; nothing written")
        return 1
    outputs = {
        os.path.join(PROJ_DIR, "project.pbxproj"): pbx,
        os.path.join(PROJ_DIR, "xcshareddata", "xcschemes", f"{TARGET}.xcscheme"): scheme,
    }
    if check:
        stale = []
        for p, t in outputs.items():
            cur = open(p, encoding="utf-8").read() if os.path.exists(p) else None
            if cur != t:
                stale.append(os.path.relpath(p, REPO))
        if stale:
            print("Xcode project is stale: " + ", ".join(stale) + " -- run python3 tools/ios/gen_xcodeproj.py")
            return 1
        print("Xcode project is up to date")
        return 0
    root = pbxproj_validate.parse(pbx)
    nsrc = sum(1 for o in root["objects"].values() if o.get("lastKnownFileType") == "sourcecode.swift")
    for p, t in outputs.items():
        print(("wrote     " if write_if_changed(p, t) else "unchanged ") + os.path.relpath(p, REPO))
    print(f"{len(root['objects'])} objects, {nsrc} Swift files; validation OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
