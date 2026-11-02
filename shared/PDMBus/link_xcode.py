#!/usr/bin/env python3
"""Links the local PDMBus package into an Xcode project and adds the shared App Group.

    python3 link_xcode.py <path/to/App.xcodeproj> <Target> [<Target> ...]

For each target it adds: the PDMBus product (package product dependency + Frameworks build file)
and the App Group `group.com.fatihgocgun.pdm` in the target's entitlements (it makes the file and
the CODE_SIGN_ENTITLEMENTS setting when they are missing). Running it again changes nothing.
"""
import hashlib
import os
import plistlib
import re
import sys

GROUP = "group.com.fatihgocgun.pdm"
PACKAGE_DIR = os.path.dirname(os.path.realpath(__file__))


def new_id(text, seed):
    n = 0
    while True:
        i = "PD" + hashlib.sha1(f"{seed}|{n}".encode()).hexdigest()[:22].upper()
        if i not in text:
            return i
        n += 1


def block(text, obj_id):
    """(start, end) of the object block `<id> ... = {` … `};` at two tabs."""
    m = re.search(r"\n\t\t" + obj_id + r"(?: /\*[^*]*\*/)? = \{", text)
    if not m:
        raise SystemExit(f"object {obj_id} not found")
    end = text.index("\n\t\t};", m.end()) + len("\n\t\t};")
    return m.start(), end


def ensure_section(text, name, after_section):
    if f"/* Begin {name} section */" in text:
        return text
    anchor = f"/* End {after_section} section */\n"
    i = text.index(anchor) + len(anchor)
    return text[:i] + f"\n/* Begin {name} section */\n/* End {name} section */\n" + text[i:]


def add_to_section(text, name, entry):
    end = f"/* End {name} section */"
    i = text.index(end)
    return text[:i] + entry + "\n" + text[i:]


def add_to_list(text, start, end, key, item):
    """Adds `item` to the list `key = ( … );` inside text[start:end]. Makes the list when missing."""
    seg = text[start:end]
    m = re.search(r"\n(\t+)" + key + r" = \(\n", seg)
    if m:
        pos = start + m.end()
        return text[:pos] + f"{m.group(1)}\t{item},\n" + text[pos:]
    m = re.search(r"\n(\t+)productName = ", seg) or re.search(r"\n(\t+)name = ", seg)
    tabs = m.group(1)
    pos = start + m.start()
    return text[:pos] + f"\n{tabs}{key} = (\n{tabs}\t{item},\n{tabs});" + text[pos:]


def target_ids(text, name):
    m = re.search(r"\n\t\t([0-9A-Z]{24}) /\* " + re.escape(name) + r" \*/ = \{\n\t\t\tisa = PBXNativeTarget;", text)
    if not m:
        raise SystemExit(f"target {name} not found")
    return m.group(1)


def entitlements(proj_dir, text, target, tid):
    s, e = block(text, tid)
    cl = re.search(r"buildConfigurationList = ([0-9A-Z]{24})", text[s:e]).group(1)
    ls, le = block(text, cl)
    configs = re.findall(r"\t\t\t\t([0-9A-Z]{24})", text[ls:le])
    paths = set()
    for c in configs:
        cs, ce = block(text, c)
        m = re.search(r"CODE_SIGN_ENTITLEMENTS = \"?([^;\"]+)\"?;", text[cs:ce])
        if m:
            paths.add(m.group(1))
            continue
        rel = f"{target}/{target}.entitlements"
        paths.add(rel)
        bs = text.index("buildSettings = {\n", cs) + len("buildSettings = {\n")
        text = text[:bs] + f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = {rel};\n" + text[bs:]
    for rel in paths:
        p = os.path.join(proj_dir, rel)
        d = {}
        if os.path.exists(p):
            with open(p, "rb") as f:
                d = plistlib.load(f)
        groups = d.setdefault("com.apple.security.application-groups", [])
        if GROUP not in groups:
            groups.append(GROUP)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                plistlib.dump(d, f)
            print(f"  entitlements: {rel} + {GROUP}")
    return text


def main():
    proj, targets = sys.argv[1], sys.argv[2:]
    pbx = os.path.join(proj, "project.pbxproj")
    proj_dir = os.path.dirname(os.path.realpath(proj))
    text = open(pbx, encoding="utf-8").read()
    rel = os.path.relpath(PACKAGE_DIR, proj_dir)

    m = re.search(r"([0-9A-Z]{24}) /\* XCLocalSwiftPackageReference \"[^\"]*PDMBus\" \*/", text)
    if m:
        ref = m.group(1)
    else:
        ref = new_id(text, proj + "ref")
        text = ensure_section(text, "XCLocalSwiftPackageReference", "XCConfigurationList")
        text = add_to_section(text, "XCLocalSwiftPackageReference",
                              f"\t\t{ref} /* XCLocalSwiftPackageReference \"{rel}\" */ = {{\n"
                              f"\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = {rel};\n\t\t}};")
        pid = re.search(r"\n\t\t([0-9A-Z]{24}) /\* Project object \*/ = \{", text).group(1)
        s, e = block(text, pid)
        seg = text[s:e]
        if "packageReferences = (" in seg:
            text = add_to_list(text, s, e, "packageReferences", f"{ref} /* XCLocalSwiftPackageReference \"{rel}\" */")
        else:
            pos = s + seg.index("\n\t\t\tpreferredProjectObjectVersion") if "preferredProjectObjectVersion" in seg \
                else s + seg.index("\n\t\t\tproductRefGroup")
            text = text[:pos] + f"\n\t\t\tpackageReferences = (\n\t\t\t\t{ref} /* XCLocalSwiftPackageReference \"{rel}\" */,\n\t\t\t);" + text[pos:]
        print(f"  package: {rel}")

    for t in targets:
        tid = target_ids(text, t)
        s, e = block(text, tid)
        if "/* PDMBus */" not in text[s:e]:
            dep = new_id(text, proj + t + "dep")
            text = ensure_section(text, "XCSwiftPackageProductDependency", "XCLocalSwiftPackageReference")
            text = add_to_section(text, "XCSwiftPackageProductDependency",
                                  f"\t\t{dep} /* PDMBus */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
                                  f"\t\t\tpackage = {ref} /* XCLocalSwiftPackageReference \"{rel}\" */;\n\t\t\tproductName = PDMBus;\n\t\t}};")
            s, e = block(text, tid)
            text = add_to_list(text, s, e, "packageProductDependencies", f"{dep} /* PDMBus */")
            # Frameworks build phase
            s, e = block(text, tid)
            fw = None
            phases = re.search(r"buildPhases = \((.*?)\);", text[s:e], re.S).group(1)
            for pid in re.findall(r"([0-9A-Z]{24})", phases):
                ps, pe = block(text, pid)
                if "isa = PBXFrameworksBuildPhase;" in text[ps:pe]:
                    fw = pid
            if fw is None:
                fw = new_id(text, proj + t + "fw")
                text = add_to_section(text, "PBXFrameworksBuildPhase",
                                      f"\t\t{fw} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
                                      f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};") \
                    if "/* Begin PBXFrameworksBuildPhase section */" in text else text
                if "/* Begin PBXFrameworksBuildPhase section */" not in text:
                    text = ensure_section(text, "PBXFrameworksBuildPhase", "PBXFileSystemSynchronizedRootGroup")
                    text = add_to_section(text, "PBXFrameworksBuildPhase",
                                          f"\t\t{fw} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
                                          f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
                s, e = block(text, tid)
                text = add_to_list(text, s, e, "buildPhases", f"{fw} /* Frameworks */")
            bf = new_id(text, proj + t + "bf")
            text = ensure_section(text, "PBXBuildFile", "PBXFileReference") if "/* Begin PBXBuildFile section */" not in text else text
            if "/* Begin PBXBuildFile section */" not in text:
                i = text.index("/* Begin ")
                text = text[:i] + "/* Begin PBXBuildFile section */\n/* End PBXBuildFile section */\n\n" + text[i:]
            text = add_to_section(text, "PBXBuildFile",
                                  f"\t\t{bf} /* PDMBus in Frameworks */ = {{isa = PBXBuildFile; productRef = {dep} /* PDMBus */; }};")
            s, e = block(text, fw)
            text = add_to_list(text, s, e, "files", f"{bf} /* PDMBus in Frameworks */")
            print(f"  target {t}: PDMBus linked")
        text = entitlements(proj_dir, text, t, tid)

    with open(pbx, "w", encoding="utf-8") as f:
        f.write(text)


if __name__ == "__main__":
    main()
