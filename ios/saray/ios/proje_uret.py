#!/usr/bin/env python3
"""Saray.xcodeproj/project.pbxproj üreticisi — tek hedef (uygulama), klasör eşitlemeli grup.
Saray/ klasörüne konan her .swift, sozluk.json ve SarayModel.mlpackage kendiliğinden derlemeye girer.   python3 proje_uret.py"""
import pathlib
YER = pathlib.Path(__file__).resolve().parent
TEAM = "EK4WY8PSFE"
I = {k: f"C6{i + 1:022X}" for i, k in enumerate(
    "proje ana urunler app grp ex cfgP cfgA src fw rs dP rP dA rA hedef".split())}

ortak = ["ALWAYS_SEARCH_USER_PATHS = NO;", "CLANG_ENABLE_MODULES = YES;", "CLANG_ENABLE_OBJC_ARC = YES;", "ENABLE_STRICT_OBJC_MSGSEND = YES;",
         "ENABLE_USER_SCRIPT_SANDBOXING = YES;", "IPHONEOS_DEPLOYMENT_TARGET = 18.0;", "LOCALIZATION_PREFERS_STRING_CATALOGS = YES;", "SDKROOT = iphoneos;"]
dbg = ortak + ["DEBUG_INFORMATION_FORMAT = dwarf;", "ENABLE_TESTABILITY = YES;", "GCC_OPTIMIZATION_LEVEL = 0;", 'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");',
               "ONLY_ACTIVE_ARCH = YES;", 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";', 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";']
rel = ortak + ['DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";', "ENABLE_NS_ASSERTIONS = NO;", "SWIFT_COMPILATION_MODE = wholemodule;", "VALIDATE_PRODUCT = YES;"]
app = ["ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;", "CODE_SIGN_STYLE = Automatic;",
       "CURRENT_PROJECT_VERSION = 1;", f"DEVELOPMENT_TEAM = {TEAM};", "ENABLE_PREVIEWS = YES;", "GENERATE_INFOPLIST_FILE = YES;", "INFOPLIST_FILE = Saray/Info.plist;",
       "INFOPLIST_KEY_CFBundleDisplayName = Saray;", 'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.education";',
       'INFOPLIST_KEY_NSCameraUsageDescription = "Evindeki eşyaları tanıyıp İngilizce adlarını üstlerinde göstermek için. Görüntü telefondan çıkmaz.";',
       "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;", "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;",
       "INFOPLIST_KEY_UILaunchScreen_Generation = YES;", "INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;",
       "INFOPLIST_KEY_UIUserInterfaceStyle = Dark;", 'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");', "MARKETING_VERSION = 1.0;",
       "PRODUCT_BUNDLE_IDENTIFIER = com.fatihgocgun.saray;", 'PRODUCT_NAME = "$(TARGET_NAME)";', 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
       "SUPPORTS_MACCATALYST = NO;", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;", "SWIFT_EMIT_LOC_STRINGS = YES;", "SWIFT_VERSION = 5.0;", "TARGETED_DEVICE_FAMILY = 1;"]

def ayar(kid, ad, satirlar):
    s = "\n".join("\t\t\t\t" + x for x in satirlar)
    return f"\t\t{kid} = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{s}\n\t\t\t}};\n\t\t\tname = {ad};\n\t\t}};\n"

def liste(kid, d, r):
    return f"\t\t{kid} = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{d},\n\t\t\t\t{r},\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n"

def faz(kid, isa):
    return f"\t\t{kid} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"

o = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXFileReference section */
\t\t{I['app']} /* Saray.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Saray.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
\t\t{I['ex']} = {{
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tInfo.plist,
\t\t\t);
\t\t\ttarget = {I['hedef']};
\t\t}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{I['grp']} /* Saray */ = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ({I['ex']}, ); path = Saray; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{faz(I['fw'], 'PBXFrameworksBuildPhase')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['ana']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['grp']},
\t\t\t\t{I['urunler']},
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['urunler']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['app']},
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{I['hedef']} /* Saray */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cfgA']};
\t\t\tbuildPhases = (
\t\t\t\t{I['src']},
\t\t\t\t{I['fw']},
\t\t\t\t{I['rs']},
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I['grp']},
\t\t\t);
\t\t\tname = Saray;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = Saray;
\t\t\tproductReference = {I['app']};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I['proje']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2630;
\t\t\t\tLastUpgradeCheck = 2630;
\t\t\t}};
\t\t\tbuildConfigurationList = {I['cfgP']};
\t\t\tdevelopmentRegion = tr;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ttr,
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['ana']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I['urunler']};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['hedef']},
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{faz(I['rs'], 'PBXResourcesBuildPhase')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{faz(I['src'], 'PBXSourcesBuildPhase')}/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{ayar(I['dP'], 'Debug', dbg)}{ayar(I['rP'], 'Release', rel)}{ayar(I['dA'], 'Debug', app)}{ayar(I['rA'], 'Release', app)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{liste(I['cfgP'], I['dP'], I['rP'])}{liste(I['cfgA'], I['dA'], I['rA'])}/* End XCConfigurationList section */
\t}};
\trootObject = {I['proje']} /* Project object */;
}}
"""
d = YER / "Saray.xcodeproj"; d.mkdir(exist_ok=True)
(d / "project.pbxproj").write_text(o, encoding="utf-8")
print("yazıldı:", d / "project.pbxproj")
