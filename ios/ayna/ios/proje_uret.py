#!/usr/bin/env python3
"""Ayna.xcodeproj üreticisi — genel: bir uygulama hedefi + istenen sayıda uzantı, klasör eşitlemeli gruplar.
Her hedef kendi klasörünü ve Ortak/'ı derler; uzantılar WIDGET bayrağıyla.   python3 proje_uret.py"""
import pathlib
YER = pathlib.Path(__file__).resolve().parent
AD, BUNDLE, TEAM, ONEK = "Ayna", "com.fatihgocgun.ayna", "EK4WY8PSFE", "C7"
UYGULAMA_AYAR = [
    'INFOPLIST_KEY_NSMicrophoneUsageDescription = "Gününü İngilizce anlatmak için. Kayıt vault\'taki Ayna klasörüne gider.";',
    'INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "Anlatımını telefonun içinde hemen İngilizce yazıya dökmek için.";',
    'INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Bugün çektiğin fotoğrafları anlatma konusu olarak göstermek için. Fotoğraf telefondan çıkmaz.";',
    'INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription = "Bugünü anlatmak ve yarınki randevuna İngilizce prova yapmak için.";',
    "INFOPLIST_KEY_UIUserInterfaceStyle = Dark;",
]
UZANTILAR = [  # (klasör, hedef adı, paket son eki)
    ("AynaWidget", "AynaWidgetExtension", "widget"),
    ("AynaKalkan", "AynaKalkanExtension", "kalkan"),
    ("AynaKalkanEylem", "AynaKalkanEylemExtension", "kalkaneylem"),
    ("AynaIzleyici", "AynaIzleyiciExtension", "izleyici"),
]
n = [0]
def k():
    n[0] += 1; return f"{ONEK}{n[0]:022X}"
P = dict(proje=k(), ana=k(), urunler=k(), ortak=k(), embed=k(), cfgP=k(), dP=k(), rP=k())
H = [dict(klasor=AD, ad=AD, urun=f"{AD}.app", bundle=BUNDLE, uygulama=True)] + \
    [dict(klasor=a, ad=b, urun=f"{b}.appex", bundle=f"{BUNDLE}.{c}", uygulama=False) for a, b, c in UZANTILAR]
for h in H:
    for x in "hedef ref grp ex cfg d r src fw rs bf px td".split(): h[x] = k()

def satirlar(l): return "\n".join("\t\t\t\t" + x for x in l if x)
ortak = ["ALWAYS_SEARCH_USER_PATHS = NO;", "CLANG_ENABLE_MODULES = YES;", "CLANG_ENABLE_OBJC_ARC = YES;", "ENABLE_STRICT_OBJC_MSGSEND = YES;",
         "ENABLE_USER_SCRIPT_SANDBOXING = YES;", "IPHONEOS_DEPLOYMENT_TARGET = 18.0;", "LOCALIZATION_PREFERS_STRING_CATALOGS = YES;", "SDKROOT = iphoneos;"]
dbg = ortak + ["DEBUG_INFORMATION_FORMAT = dwarf;", "ENABLE_TESTABILITY = YES;", "GCC_OPTIMIZATION_LEVEL = 0;", 'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");',
               "ONLY_ACTIVE_ARCH = YES;", 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";', 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";']
rel = ortak + ['DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";', "ENABLE_NS_ASSERTIONS = NO;", "SWIFT_COMPILATION_MODE = wholemodule;", "VALIDATE_PRODUCT = YES;"]

def hedef_ayar(h):
    s = [f"CODE_SIGN_ENTITLEMENTS = {h['klasor']}/{h['klasor']}.entitlements;", "CODE_SIGN_STYLE = Automatic;", "CURRENT_PROJECT_VERSION = 1;",
         f"DEVELOPMENT_TEAM = {TEAM};", "GENERATE_INFOPLIST_FILE = YES;", f"INFOPLIST_FILE = {h['klasor']}/Info.plist;", f"INFOPLIST_KEY_CFBundleDisplayName = {AD};",
         "MARKETING_VERSION = 1.0;", f"PRODUCT_BUNDLE_IDENTIFIER = {h['bundle']};", 'PRODUCT_NAME = "$(TARGET_NAME)";', 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
         "SWIFT_EMIT_LOC_STRINGS = YES;", "SWIFT_VERSION = 5.0;", "TARGETED_DEVICE_FAMILY = 1;"]
    if h["uygulama"]:
        s += ["ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;", "ENABLE_PREVIEWS = YES;",
              'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.education";', "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;",
              "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;", "INFOPLIST_KEY_UILaunchScreen_Generation = YES;",
              "INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;", 'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
              "SUPPORTS_MACCATALYST = NO;", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;"] + UYGULAMA_AYAR
    else:
        s += ["SKIP_INSTALL = YES;", 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "WIDGET $(inherited)";', 'INFOPLIST_KEY_NSHumanReadableCopyright = "";',
              'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks");']
    return s

def ayar(kid, ad, l): return f"\t\t{kid} = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{satirlar(l)}\n\t\t\t}};\n\t\t\tname = {ad};\n\t\t}};\n"
def liste(kid, d, r): return f"\t\t{kid} = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{d},\n\t\t\t\t{r},\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n"
def faz(kid, isa, dosya=()):
    f = "".join(f"\t\t\t\t{x},\n" for x in dosya)
    return f"\t\t{kid} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{f}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"
def ls(l): return "".join(f"\t\t\t\t{x},\n" for x in l)

app, uz = H[0], H[1:]
o = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n/* Begin PBXBuildFile section */\n"
for h in uz: o += f"\t\t{h['bf']} = {{isa = PBXBuildFile; fileRef = {h['ref']}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
o += "/* End PBXBuildFile section */\n\n/* Begin PBXContainerItemProxy section */\n"
for h in uz: o += f"\t\t{h['px']} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {P['proje']};\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {h['hedef']};\n\t\t\tremoteInfo = {h['ad']};\n\t\t}};\n"
o += "/* End PBXContainerItemProxy section */\n\n/* Begin PBXCopyFilesBuildPhase section */\n"
o += f"\t\t{P['embed']} = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n{ls(h['bf'] for h in uz)}\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"
o += "/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXFileReference section */\n"
for h in H:
    t = "wrapper.application" if h["uygulama"] else '"wrapper.app-extension"'
    o += f"\t\t{h['ref']} = {{isa = PBXFileReference; explicitFileType = {t}; includeInIndex = 0; path = {h['urun']}; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
o += "/* End PBXFileReference section */\n\n/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */\n"
for h in H: o += f"\t\t{h['ex']} = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n\t\t\t\t{h['klasor']}.entitlements,\n\t\t\t\tInfo.plist,\n\t\t\t);\n\t\t\ttarget = {h['hedef']};\n\t\t}};\n"
o += "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n"
for h in H: o += f"\t\t{h['grp']} = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ({h['ex']}, ); path = {h['klasor']}; sourceTree = \"<group>\"; }};\n"
o += f"\t\t{P['ortak']} = {{isa = PBXFileSystemSynchronizedRootGroup; path = Ortak; sourceTree = \"<group>\"; }};\n"
o += "/* End PBXFileSystemSynchronizedRootGroup section */\n\n/* Begin PBXFrameworksBuildPhase section */\n" + "".join(faz(h['fw'], "PBXFrameworksBuildPhase") for h in H)
o += "/* End PBXFrameworksBuildPhase section */\n\n/* Begin PBXGroup section */\n"
o += f"\t\t{P['ana']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{ls([h['grp'] for h in H] + [P['ortak'], P['urunler']])}\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
o += f"\t\t{P['urunler']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{ls(h['ref'] for h in H)}\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
o += "/* End PBXGroup section */\n\n/* Begin PBXNativeTarget section */\n"
for h in H:
    fazlar = [h['src'], h['fw'], h['rs']] + ([P['embed']] if h["uygulama"] else [])
    bag = [x['td'] for x in uz] if h["uygulama"] else []
    tip = "com.apple.product-type.application" if h["uygulama"] else "com.apple.product-type.app-extension"
    o += (f"\t\t{h['hedef']} = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {h['cfg']};\n\t\t\tbuildPhases = (\n{ls(fazlar)}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
          f"\t\t\tdependencies = (\n{ls(bag)}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n{ls([h['grp'], P['ortak']])}\t\t\t);\n\t\t\tname = {h['ad']};\n"
          f"\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {h['ad']};\n\t\t\tproductReference = {h['ref']};\n\t\t\tproductType = \"{tip}\";\n\t\t}};\n")
o += "/* End PBXNativeTarget section */\n\n/* Begin PBXProject section */\n"
o += (f"\t\t{P['proje']} = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2630;\n\t\t\t\tLastUpgradeCheck = 2630;\n\t\t\t}};\n"
      f"\t\t\tbuildConfigurationList = {P['cfgP']};\n\t\t\tdevelopmentRegion = tr;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ttr,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
      f"\t\t\tmainGroup = {P['ana']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {P['urunler']};\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
      f"\t\t\ttargets = (\n{ls(h['hedef'] for h in H)}\t\t\t);\n\t\t}};\n")
o += "/* End PBXProject section */\n\n/* Begin PBXResourcesBuildPhase section */\n" + "".join(faz(h['rs'], "PBXResourcesBuildPhase") for h in H)
o += "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */\n" + "".join(faz(h['src'], "PBXSourcesBuildPhase") for h in H)
o += "/* End PBXSourcesBuildPhase section */\n\n/* Begin PBXTargetDependency section */\n"
for h in uz: o += f"\t\t{h['td']} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {h['hedef']};\n\t\t\ttargetProxy = {h['px']};\n\t\t}};\n"
o += "/* End PBXTargetDependency section */\n\n/* Begin XCBuildConfiguration section */\n" + ayar(P['dP'], "Debug", dbg) + ayar(P['rP'], "Release", rel)
for h in H: o += ayar(h['d'], "Debug", hedef_ayar(h)) + ayar(h['r'], "Release", hedef_ayar(h))
o += "/* End XCBuildConfiguration section */\n\n/* Begin XCConfigurationList section */\n" + liste(P['cfgP'], P['dP'], P['rP'])
for h in H: o += liste(h['cfg'], h['d'], h['r'])
o += f"/* End XCConfigurationList section */\n\t}};\n\trootObject = {P['proje']};\n}}\n"
d = YER / f"{AD}.xcodeproj"; d.mkdir(exist_ok=True); (d / "project.pbxproj").write_text(o, encoding="utf-8")
print("yazıldı:", d / "project.pbxproj")
