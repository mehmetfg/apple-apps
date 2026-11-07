#!/usr/bin/env python3
"""Ufuk.xcodeproj/project.pbxproj üreticisi. İki hedef: Ufuk (uygulama) · UfukWidgetExtension (widget + Canlı Etkinlik).
Klasör eşitlemeli gruplar kullanır: yeni .swift dosyası klasöre konunca Xcode kendiliğinden görür.  python3 proje_uret.py"""
import pathlib
YER = pathlib.Path(__file__).resolve().parent
TEAM = "EK4WY8PSFE"
n = [0]
def kimlik():
    n[0] += 1
    return f"D7{n[0]:022X}"

G = {k: kimlik() for k in ["proje", "ana", "urunler", "app", "wid", "pay", "grpK", "grpW", "grpP", "grpO",
     "exK", "exW", "exP", "cfgProje", "cfgK", "cfgW", "cfgP", "bpK", "bpW", "bpP", "frK", "frW", "frP", "rsK", "rsW", "rsP",
     "tdW", "tdP", "pxW", "pxP", "embed", "bfW", "bfP", "dbgProje", "relProje", "dbgK", "relK", "dbgW", "relW", "dbgP", "relP",
     "tgK", "tgW", "tgP"]}

def hedef_ayar(ad, bundle, ent, plist, widget=False, uygulama=False, paylas=False):
    s = [f"CODE_SIGN_ENTITLEMENTS = {ent};", "CODE_SIGN_STYLE = Automatic;", "CURRENT_PROJECT_VERSION = 1;",
         f"DEVELOPMENT_TEAM = {TEAM};", "GENERATE_INFOPLIST_FILE = YES;", f"INFOPLIST_FILE = {plist};",
         'INFOPLIST_KEY_CFBundleDisplayName = Ufuk;', 'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks"' + ('' if uygulama else ', "@executable_path/../../Frameworks"') + ');',
         "MARKETING_VERSION = 1.0;", f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};", 'PRODUCT_NAME = "$(TARGET_NAME)";',
         'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";', "SWIFT_EMIT_LOC_STRINGS = YES;", "SWIFT_VERSION = 5.0;", "TARGETED_DEVICE_FAMILY = 1;"]
    if uygulama:
        s += ["ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
              "ENABLE_PREVIEWS = YES;", 'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.weather";',
              "INFOPLIST_KEY_UIUserInterfaceStyle = Dark;", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;",
              "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;", "INFOPLIST_KEY_UILaunchScreen_Generation = YES;",
              "INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;", "INFOPLIST_KEY_NSSupportsLiveActivities = YES;",
              'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Haritada ev ve işini seçerken seni bulmak, kendi yerlerine vardığını anlamak ve başlattığın rotayı (ekran kilitliyken de) kaydetmek için.";',
              'INFOPLIST_KEY_NSHealthShareUsageDescription = "Havanın adımına, yürüyüşüne, bisikletine ve uykuna etkisini göstermek için. Veri telefonda kalır.";',
              "SUPPORTS_MACCATALYST = NO;", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;"]
    else:
        s += ["SKIP_INSTALL = YES;", 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "WIDGET $(inherited)";', 'INFOPLIST_KEY_NSHumanReadableCopyright = "";',
              "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;" if widget else ""]
    return "\n".join("\t\t\t\t" + x for x in s if x)

def cfg(kid, ad, ayar):
    return f"\t\t{kid} /* {ad} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{ayar}\n\t\t\t}};\n\t\t\tname = {ad};\n\t\t}};\n"

proje_ortak = ["ALWAYS_SEARCH_USER_PATHS = NO;", "CLANG_ENABLE_MODULES = YES;", "CLANG_ENABLE_OBJC_ARC = YES;", "ENABLE_STRICT_OBJC_MSGSEND = YES;",
               "ENABLE_USER_SCRIPT_SANDBOXING = YES;", "IPHONEOS_DEPLOYMENT_TARGET = 18.0;", "LOCALIZATION_PREFERS_STRING_CATALOGS = YES;", "SDKROOT = iphoneos;"]
dbg = "\n".join("\t\t\t\t" + x for x in proje_ortak + ["COPY_PHASE_STRIP = NO;", "DEBUG_INFORMATION_FORMAT = dwarf;", "ENABLE_TESTABILITY = YES;",
      "GCC_OPTIMIZATION_LEVEL = 0;", 'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");', "ONLY_ACTIVE_ARCH = YES;",
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";', 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";'])
rel = "\n".join("\t\t\t\t" + x for x in proje_ortak + ["COPY_PHASE_STRIP = NO;", 'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";', "ENABLE_NS_ASSERTIONS = NO;",
      "SWIFT_COMPILATION_MODE = wholemodule;", "VALIDATE_PRODUCT = YES;"])

def cfglist(kid, ad, d, r):
    return (f"\t\t{kid} /* Build configuration list for {ad} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{d} /* Debug */,\n\t\t\t\t{r} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")

def bos_faz(kid, isa, ad):
    return f"\t\t{kid} /* {ad} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"

def istisna(kid, ad, hedef, dosyalar):
    d = "".join(f"\t\t\t\t{x},\n" for x in dosyalar)
    return f"\t\t{kid} /* Exceptions for \"{ad}\" */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n{d}\t\t\t);\n\t\t\ttarget = {hedef};\n\t\t}};\n"

def kok(kid, yol, ex=None):
    e = f"exceptions = ({ex}, ); " if ex else ""
    return f"\t\t{kid} /* {yol} */ = {{isa = PBXFileSystemSynchronizedRootGroup; {e}path = {yol}; sourceTree = \"<group>\"; }};\n"

def hedef(kid, ad, tip, ayarlist, fazlar, bagimli, gruplar, urun):
    f = "".join(f"\t\t\t\t{x},\n" for x in fazlar); b = "".join(f"\t\t\t\t{x},\n" for x in bagimli); g = "".join(f"\t\t\t\t{x},\n" for x in gruplar)
    return (f"\t\t{kid} /* {ad} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {ayarlist};\n\t\t\tbuildPhases = (\n{f}\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{b}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n{g}\t\t\t);\n"
            f"\t\t\tname = {ad};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {ad};\n\t\t\tproductReference = {urun};\n\t\t\tproductType = \"{tip}\";\n\t\t}};\n")

# PBXContainerItemProxy + TargetDependency (iki uzantı)
def proxy(kid, hedef_id, ad):
    return f"\t\t{kid} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {G['proje']} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {hedef_id};\n\t\t\tremoteInfo = {ad};\n\t\t}};\n"
def bagimlilik(kid, hedef_id, px, ad):
    return f"\t\t{kid} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {hedef_id} /* {ad} */;\n\t\t\ttargetProxy = {px} /* PBXContainerItemProxy */;\n\t\t}};\n"

out = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n"
out += "/* Begin PBXBuildFile section */\n"
out += f"\t\t{G['bfW']} /* UfukWidgetExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {G['wid']}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
out += "/* End PBXBuildFile section */\n\n/* Begin PBXContainerItemProxy section */\n"
out += proxy(G['pxW'], G['tgW'], "UfukWidgetExtension")
out += "/* End PBXContainerItemProxy section */\n\n/* Begin PBXCopyFilesBuildPhase section */\n"
out += (f"\t\t{G['embed']} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n"
        f"\t\t\tfiles = (\n\t\t\t\t{G['bfW']},\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
out += "/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXFileReference section */\n"
out += f"\t\t{G['app']} /* Ufuk.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Ufuk.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
out += f"\t\t{G['wid']} /* UfukWidgetExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = UfukWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
out += "/* End PBXFileReference section */\n\n/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */\n"
out += istisna(G['exK'], "Ufuk folder in Ufuk target", G['tgK'], ["Ufuk.entitlements", "Info.plist"])
out += istisna(G['exW'], "UfukWidget folder in UfukWidgetExtension target", G['tgW'], ["UfukWidget.entitlements", "Info.plist"])
out += "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n"
out += kok(G['grpK'], "Ufuk", G['exK']) + kok(G['grpW'], "UfukWidget", G['exW']) + kok(G['grpO'], "Ortak")
out += "/* End PBXFileSystemSynchronizedRootGroup section */\n\n/* Begin PBXFrameworksBuildPhase section */\n"
out += bos_faz(G['frK'], "PBXFrameworksBuildPhase", "Frameworks") + bos_faz(G['frW'], "PBXFrameworksBuildPhase", "Frameworks")
out += "/* End PBXFrameworksBuildPhase section */\n\n/* Begin PBXGroup section */\n"
out += (f"\t\t{G['ana']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{G['grpK']},\n\t\t\t\t{G['grpW']},\n\t\t\t\t{G['grpO']},\n\t\t\t\t{G['urunler']},\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
out += (f"\t\t{G['urunler']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{G['app']},\n\t\t\t\t{G['wid']},\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
out += "/* End PBXGroup section */\n\n/* Begin PBXNativeTarget section */\n"
out += hedef(G['tgK'], "Ufuk", "com.apple.product-type.application", G['cfgK'], [G['bpK'], G['frK'], G['rsK'], G['embed']], [G['tdW']], [G['grpK'], G['grpO']], G['app'])
out += hedef(G['tgW'], "UfukWidgetExtension", "com.apple.product-type.app-extension", G['cfgW'], [G['bpW'], G['frW'], G['rsW']], [], [G['grpW'], G['grpO']], G['wid'])
out += "/* End PBXNativeTarget section */\n\n/* Begin PBXProject section */\n"
out += (f"\t\t{G['proje']} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2630;\n\t\t\t\tLastUpgradeCheck = 2630;\n"
        f"\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{G['tgK']} = {{CreatedOnToolsVersion = 26.3;}};\n\t\t\t\t\t{G['tgW']} = {{CreatedOnToolsVersion = 26.3;}};\n\t\t\t\t}};\n\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {G['cfgProje']} /* Build configuration list for PBXProject \"Ufuk\" */;\n\t\t\tdevelopmentRegion = tr;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ttr,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {G['ana']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {G['urunler']} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
        f"\t\t\ttargets = (\n\t\t\t\t{G['tgK']},\n\t\t\t\t{G['tgW']},\n\t\t\t);\n\t\t}};\n")
out += "/* End PBXProject section */\n\n/* Begin PBXResourcesBuildPhase section */\n"
out += bos_faz(G['rsK'], "PBXResourcesBuildPhase", "Resources") + bos_faz(G['rsW'], "PBXResourcesBuildPhase", "Resources")
out += "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */\n"
out += bos_faz(G['bpK'], "PBXSourcesBuildPhase", "Sources") + bos_faz(G['bpW'], "PBXSourcesBuildPhase", "Sources")
out += "/* End PBXSourcesBuildPhase section */\n\n/* Begin PBXTargetDependency section */\n"
out += bagimlilik(G['tdW'], G['tgW'], G['pxW'], "UfukWidgetExtension")
out += "/* End PBXTargetDependency section */\n\n/* Begin XCBuildConfiguration section */\n"
out += cfg(G['dbgProje'], "Debug", dbg) + cfg(G['relProje'], "Release", rel)
a = hedef_ayar("Ufuk", "com.fatihgocgun.ufuk", "Ufuk/Ufuk.entitlements", "Ufuk/Info.plist", uygulama=True)
w = hedef_ayar("W", "com.fatihgocgun.ufuk.widget", "UfukWidget/UfukWidget.entitlements", "UfukWidget/Info.plist", widget=True)
out += cfg(G['dbgK'], "Debug", a) + cfg(G['relK'], "Release", a) + cfg(G['dbgW'], "Debug", w) + cfg(G['relW'], "Release", w)
out += "/* End XCBuildConfiguration section */\n\n/* Begin XCConfigurationList section */\n"
out += cfglist(G['cfgProje'], 'PBXProject "Ufuk"', G['dbgProje'], G['relProje']) + cfglist(G['cfgK'], 'PBXNativeTarget "Ufuk"', G['dbgK'], G['relK'])
out += cfglist(G['cfgW'], 'PBXNativeTarget "UfukWidgetExtension"', G['dbgW'], G['relW'])
out += f"/* End XCConfigurationList section */\n\t}};\n\trootObject = {G['proje']} /* Project object */;\n}}\n"
d = YER / "Ufuk.xcodeproj"; d.mkdir(exist_ok=True)
(d / "project.pbxproj").write_text(out, encoding="utf-8")
print("yazıldı:", d / "project.pbxproj")
# PDM Ağı: ortak PDMBus paketi + group.com.fatihgocgun.pdm (yalnız uygulama hedefi)
import subprocess, sys
subprocess.run([sys.executable, str(YER.parent.parent.parent / "shared/PDMBus/link_xcode.py"), str(d), "Ufuk"], check=True)
