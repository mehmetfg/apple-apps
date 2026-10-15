#!/usr/bin/env python3
"""Kenar.xcodeproj/project.pbxproj üreticisi. Üç hedef: Kenar (uygulama) · KenarWidgetExtension · KenarPaylasExtension.
Klasör eşitlemeli gruplar kullanır: yeni .swift dosyası klasöre konunca Xcode kendiliğinden görür.  python3 proje_uret.py"""
import pathlib
YER = pathlib.Path(__file__).resolve().parent
TEAM = "EK4WY8PSFE"
n = [0]
def kimlik():
    n[0] += 1
    return f"C5{n[0]:022X}"

G = {k: kimlik() for k in ["proje", "ana", "urunler", "app", "wid", "pay", "grpK", "grpW", "grpP", "grpO",
     "exK", "exW", "exP", "cfgProje", "cfgK", "cfgW", "cfgP", "bpK", "bpW", "bpP", "frK", "frW", "frP", "rsK", "rsW", "rsP",
     "tdW", "tdP", "pxW", "pxP", "embed", "bfW", "bfP", "dbgProje", "relProje", "dbgK", "relK", "dbgW", "relW", "dbgP", "relP",
     "tgK", "tgW", "tgP"]}

def hedef_ayar(ad, bundle, ent, plist, widget=False, uygulama=False, paylas=False):
    s = [f"CODE_SIGN_ENTITLEMENTS = {ent};", "CODE_SIGN_STYLE = Automatic;", "CURRENT_PROJECT_VERSION = 1;",
         f"DEVELOPMENT_TEAM = {TEAM};", "GENERATE_INFOPLIST_FILE = YES;", f"INFOPLIST_FILE = {plist};",
         'INFOPLIST_KEY_CFBundleDisplayName = Kenar;', 'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks"' + ('' if uygulama else ', "@executable_path/../../Frameworks"') + ');',
         "MARKETING_VERSION = 1.0;", f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};", 'PRODUCT_NAME = "$(TARGET_NAME)";',
         'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";', "SWIFT_EMIT_LOC_STRINGS = YES;", "SWIFT_VERSION = 5.0;", "TARGETED_DEVICE_FAMILY = 1;"]
    if uygulama:
        s += ["ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
              "ENABLE_PREVIEWS = YES;", 'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.education";',
              "INFOPLIST_KEY_UIUserInterfaceStyle = Automatic;", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;",
              "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;", "INFOPLIST_KEY_UILaunchScreen_Generation = YES;",
              "INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;", "INFOPLIST_KEY_NSSupportsLiveActivities = YES;",
              'INFOPLIST_KEY_NSCameraUsageDescription = "Kâğıt kitaptaki cümleyi ve ISBN barkodunu okumak için.";',
              'INFOPLIST_KEY_NSMicrophoneUsageDescription = "Feynman dakikası: kitabı kapatıp sesli anlatmak için. Kayıt vault\'taki Kenar klasörüne gider.";',
              'INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "Anlatımı telefonun içinde ön dökümle yazıya çevirip atladığın kanıtı hemen göstermek için.";',
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
out += f"\t\t{G['bfW']} /* KenarWidgetExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {G['wid']}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
out += f"\t\t{G['bfP']} /* KenarPaylasExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {G['pay']}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
out += "/* End PBXBuildFile section */\n\n/* Begin PBXContainerItemProxy section */\n"
out += proxy(G['pxW'], G['tgW'], "KenarWidgetExtension") + proxy(G['pxP'], G['tgP'], "KenarPaylasExtension")
out += "/* End PBXContainerItemProxy section */\n\n/* Begin PBXCopyFilesBuildPhase section */\n"
out += (f"\t\t{G['embed']} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n"
        f"\t\t\tfiles = (\n\t\t\t\t{G['bfW']},\n\t\t\t\t{G['bfP']},\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
out += "/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXFileReference section */\n"
out += f"\t\t{G['app']} /* Kenar.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Kenar.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
out += f"\t\t{G['wid']} /* KenarWidgetExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = KenarWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
out += f"\t\t{G['pay']} /* KenarPaylasExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = KenarPaylasExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
out += "/* End PBXFileReference section */\n\n/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */\n"
out += istisna(G['exK'], "Kenar folder in Kenar target", G['tgK'], ["Kenar.entitlements", "Info.plist"])
out += istisna(G['exW'], "KenarWidget folder in KenarWidgetExtension target", G['tgW'], ["KenarWidget.entitlements", "Info.plist"])
out += istisna(G['exP'], "KenarPaylas folder in KenarPaylasExtension target", G['tgP'], ["KenarPaylas.entitlements", "Info.plist"])
out += "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n"
out += kok(G['grpK'], "Kenar", G['exK']) + kok(G['grpW'], "KenarWidget", G['exW']) + kok(G['grpP'], "KenarPaylas", G['exP']) + kok(G['grpO'], "Ortak")
out += "/* End PBXFileSystemSynchronizedRootGroup section */\n\n/* Begin PBXFrameworksBuildPhase section */\n"
out += bos_faz(G['frK'], "PBXFrameworksBuildPhase", "Frameworks") + bos_faz(G['frW'], "PBXFrameworksBuildPhase", "Frameworks") + bos_faz(G['frP'], "PBXFrameworksBuildPhase", "Frameworks")
out += "/* End PBXFrameworksBuildPhase section */\n\n/* Begin PBXGroup section */\n"
out += (f"\t\t{G['ana']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{G['grpK']},\n\t\t\t\t{G['grpW']},\n\t\t\t\t{G['grpP']},\n\t\t\t\t{G['grpO']},\n\t\t\t\t{G['urunler']},\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
out += (f"\t\t{G['urunler']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{G['app']},\n\t\t\t\t{G['wid']},\n\t\t\t\t{G['pay']},\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
out += "/* End PBXGroup section */\n\n/* Begin PBXNativeTarget section */\n"
out += hedef(G['tgK'], "Kenar", "com.apple.product-type.application", G['cfgK'], [G['bpK'], G['frK'], G['rsK'], G['embed']], [G['tdW'], G['tdP']], [G['grpK'], G['grpO']], G['app'])
out += hedef(G['tgW'], "KenarWidgetExtension", "com.apple.product-type.app-extension", G['cfgW'], [G['bpW'], G['frW'], G['rsW']], [], [G['grpW'], G['grpO']], G['wid'])
out += hedef(G['tgP'], "KenarPaylasExtension", "com.apple.product-type.app-extension", G['cfgP'], [G['bpP'], G['frP'], G['rsP']], [], [G['grpP'], G['grpO']], G['pay'])
out += "/* End PBXNativeTarget section */\n\n/* Begin PBXProject section */\n"
out += (f"\t\t{G['proje']} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2630;\n\t\t\t\tLastUpgradeCheck = 2630;\n"
        f"\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{G['tgK']} = {{CreatedOnToolsVersion = 26.3;}};\n\t\t\t\t\t{G['tgW']} = {{CreatedOnToolsVersion = 26.3;}};\n\t\t\t\t\t{G['tgP']} = {{CreatedOnToolsVersion = 26.3;}};\n\t\t\t\t}};\n\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {G['cfgProje']} /* Build configuration list for PBXProject \"Kenar\" */;\n\t\t\tdevelopmentRegion = tr;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ttr,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {G['ana']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {G['urunler']} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
        f"\t\t\ttargets = (\n\t\t\t\t{G['tgK']},\n\t\t\t\t{G['tgW']},\n\t\t\t\t{G['tgP']},\n\t\t\t);\n\t\t}};\n")
out += "/* End PBXProject section */\n\n/* Begin PBXResourcesBuildPhase section */\n"
out += bos_faz(G['rsK'], "PBXResourcesBuildPhase", "Resources") + bos_faz(G['rsW'], "PBXResourcesBuildPhase", "Resources") + bos_faz(G['rsP'], "PBXResourcesBuildPhase", "Resources")
out += "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */\n"
out += bos_faz(G['bpK'], "PBXSourcesBuildPhase", "Sources") + bos_faz(G['bpW'], "PBXSourcesBuildPhase", "Sources") + bos_faz(G['bpP'], "PBXSourcesBuildPhase", "Sources")
out += "/* End PBXSourcesBuildPhase section */\n\n/* Begin PBXTargetDependency section */\n"
out += bagimlilik(G['tdW'], G['tgW'], G['pxW'], "KenarWidgetExtension") + bagimlilik(G['tdP'], G['tgP'], G['pxP'], "KenarPaylasExtension")
out += "/* End PBXTargetDependency section */\n\n/* Begin XCBuildConfiguration section */\n"
out += cfg(G['dbgProje'], "Debug", dbg) + cfg(G['relProje'], "Release", rel)
a = hedef_ayar("Kenar", "com.fatihgocgun.kenar", "Kenar/Kenar.entitlements", "Kenar/Info.plist", uygulama=True)
w = hedef_ayar("W", "com.fatihgocgun.kenar.widget", "KenarWidget/KenarWidget.entitlements", "KenarWidget/Info.plist", widget=True)
p = hedef_ayar("P", "com.fatihgocgun.kenar.paylas", "KenarPaylas/KenarPaylas.entitlements", "KenarPaylas/Info.plist", paylas=True)
out += cfg(G['dbgK'], "Debug", a) + cfg(G['relK'], "Release", a) + cfg(G['dbgW'], "Debug", w) + cfg(G['relW'], "Release", w) + cfg(G['dbgP'], "Debug", p) + cfg(G['relP'], "Release", p)
out += "/* End XCBuildConfiguration section */\n\n/* Begin XCConfigurationList section */\n"
out += cfglist(G['cfgProje'], 'PBXProject "Kenar"', G['dbgProje'], G['relProje']) + cfglist(G['cfgK'], 'PBXNativeTarget "Kenar"', G['dbgK'], G['relK'])
out += cfglist(G['cfgW'], 'PBXNativeTarget "KenarWidgetExtension"', G['dbgW'], G['relW']) + cfglist(G['cfgP'], 'PBXNativeTarget "KenarPaylasExtension"', G['dbgP'], G['relP'])
out += f"/* End XCConfigurationList section */\n\t}};\n\trootObject = {G['proje']} /* Project object */;\n}}\n"
d = YER / "Kenar.xcodeproj"; d.mkdir(exist_ok=True)
(d / "project.pbxproj").write_text(out, encoding="utf-8")
print("yazıldı:", d / "project.pbxproj")
