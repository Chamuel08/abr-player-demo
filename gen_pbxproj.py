#!/usr/bin/env python3
# Generates a minimal Xcode project.pbxproj for ABRPlayerDemo
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ABRPlayerDemo")

# Source files (relative to ABRPlayerDemo/ABRPlayerDemo)
sources = [
    "ABRPlayerDemoApp.swift",
    "ContentView.swift",
    "ABR/ABRPlayerController.swift",
    "ABR/ABRController.swift",
    "ABR/BBAController.swift",
    "ABR/HLSVariantParser.swift",
    "ABR/MPCController.swift",
    "ABR/QoSObservers.swift",
    "ABR/ThroughputEstimator.swift",
    "Models/HLSVariant.swift",
    "Models/QoSMetrics.swift",
    "Models/SwitchLog.swift",
    "Views/PlayerView.swift",
    "Views/QoSDashboard.swift",
    "Views/SwitchLogView.swift",
]

# Assign stable 24-char hex UUIDs
def uid(n):
    return f"{n:024x}"

i = 1
file_refs = {}
build_files = {}
for s in sources:
    file_refs[s] = uid(i); i += 1
    build_files[s] = uid(i); i += 1

PBXBuildFile = uid(100)
PBXFileReference = uid(101)
PBXGroup = uid(102)
PBXNativeTarget = uid(103)
PBXProject = uid(104)
PBXResourcesBuildPhase = uid(105)
PBXSourcesBuildPhase = uid(106)
XCBuildConfiguration = uid(107)
XCConfigurationList = uid(108)
XCConfigurationList2 = uid(109)
mainGroup = uid(110)
appGroup = uid(111)
abrGroup = uid(112)
modelsGroup = uid(113)
viewsGroup = uid(114)
assetsRef = uid(115)
infoPlistRef = uid(116)
assetsBuildFile = uid(117)
projBuildConfig = uid(118)
targetBuildConfig = uid(119)
rootObj = uid(120)

lines = []
A = lines.append

A("// !$*UTF8*$!")
A("{")
A("\tarchiveVersion = 1;")
A("\tclasses = {};")
A("\tobjectVersion = 56;")
A("\tobjects = {")
A("")
A("/* Begin PBXBuildFile section */")
for s in sources:
    A(f"\t\t{build_files[s]} /* {s} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[s]} /* {s} */; }};")
A(f"\t\t{assetsBuildFile} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assetsRef} /* Assets.xcassets */; }};")
A("/* End PBXBuildFile section */")
A("")
A("/* Begin PBXFileReference section */")
for s in sources:
    A(f"\t\t{file_refs[s]} /* {s} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {os.path.basename(s)!r}; sourceTree = \"<group>\"; }};")
A(f"\t\t{assetsRef} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = \"Assets.xcassets\"; sourceTree = \"<group>\"; }};")
A(f"\t\t{infoPlistRef} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"Info.plist\"; sourceTree = \"<group>\"; }};")
A(f"\t\t{rootObj} /* ABRPlayerDemo.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \"ABRPlayerDemo.app\"; sourceTree = BUILT_PRODUCTS_DIR; }};")
A("/* End PBXFileReference section */")
A("")
A("/* Begin PBXFrameworksBuildPhase section */")
A(f"\t\t{uid(200)} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; }};")
A("/* End PBXFrameworksBuildPhase section */")
A("")
A("/* Begin PBXGroup section */")
# sub-groups
A(f"\t\t{abrGroup} /* ABR */ = {{isa = PBXGroup; children = (")
for s in sources:
    if s.startswith("ABR/"):
        A(f"\t\t\t{file_refs[s]} /* {os.path.basename(s)} */,")
A(f"\t\t); path = \"ABR\"; sourceTree = \"<group>\"; }};")
A(f"\t\t{modelsGroup} /* Models */ = {{isa = PBXGroup; children = (")
for s in sources:
    if s.startswith("Models/"):
        A(f"\t\t\t{file_refs[s]} /* {os.path.basename(s)} */,")
A(f"\t\t); path = \"Models\"; sourceTree = \"<group>\"; }};")
A(f"\t\t{viewsGroup} /* Views */ = {{isa = PBXGroup; children = (")
for s in sources:
    if s.startswith("Views/"):
        A(f"\t\t\t{file_refs[s]} /* {os.path.basename(s)} */,")
A(f"\t\t); path = \"Views\"; sourceTree = \"<group>\"; }};")
A(f"\t\t{appGroup} /* ABRPlayerDemo */ = {{isa = PBXGroup; children = (")
A(f"\t\t\t{file_refs['ABRPlayerDemoApp.swift']} /* ABRPlayerDemoApp.swift */,")
A(f"\t\t\t{file_refs['ContentView.swift']} /* ContentView.swift */,")
A(f"\t\t\t{abrGroup} /* ABR */,")
A(f"\t\t\t{modelsGroup} /* Models */,")
A(f"\t\t\t{viewsGroup} /* Views */,")
A(f"\t\t\t{assetsRef} /* Assets.xcassets */,")
A(f"\t\t\t{infoPlistRef} /* Info.plist */,")
A(f"\t\t); path = \"ABRPlayerDemo\"; sourceTree = \"<group>\"; }};")
A(f"\t\t{mainGroup} /* */ = {{isa = PBXGroup; children = (")
A(f"\t\t\t{appGroup} /* ABRPlayerDemo */,")
A(f"\t\t\t{rootObj} /* ABRPlayerDemo.app */,")
A(f"\t\t); sourceTree = \"<group>\"; }};")
A("/* End PBXGroup section */")
A("")
A("/* Begin PBXNativeTarget section */")
A(f"\t\t{PBXNativeTarget} /* ABRPlayerDemo */ = {{isa = PBXNativeTarget; buildConfigurationList = {XCConfigurationList2} /* Build configuration list for PBXNativeTarget */; buildPhases = (")
A(f"\t\t\t{PBXSourcesBuildPhase} /* Sources */,")
A(f"\t\t\t{PBXResourcesBuildPhase} /* Resources */,")
A(f"\t\t); buildRules = ( ); dependencies = ( ); name = \"ABRPlayerDemo\"; productName = \"ABRPlayerDemo\"; productReference = {rootObj} /* ABRPlayerDemo.app */; productType = \"com.apple.product-type.application\"; }};")
A("/* End PBXNativeTarget section */")
A("")
A("/* Begin PBXProject section */")
A(f"\t\t{PBXProject} /* Project object */ = {{isa = PBXProject; attributes = {{LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; }}; buildConfigurationList = {XCConfigurationList} /* Build configuration list for PBXProject */; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = \"en\"; hasScannedForEncodings = 0; knownRegions = (\"en\", \"Base\", ); mainGroup = {mainGroup} /* */; packageReferences = ( ); productRefGroup = {mainGroup} /* */; projectDirPath = \"\"; projectRoot = \"\"; targets = (")
A(f"\t\t\t{PBXNativeTarget} /* ABRPlayerDemo */,")
A(f"\t\t); }};")
A("/* End PBXProject section */")
A("")
A("/* Begin PBXResourcesBuildPhase section */")
A(f"\t\t{PBXResourcesBuildPhase} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (")
A(f"\t\t\t{assetsBuildFile} /* Assets.xcassets in Resources */,")
A(f"\t\t); runOnlyForDeploymentPostprocessing = 0; }};")
A("/* End PBXResourcesBuildPhase section */")
A("")
A("/* Begin PBXSourcesBuildPhase section */")
A(f"\t\t{PBXSourcesBuildPhase} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (")
for s in sources:
    A(f"\t\t\t{build_files[s]} /* {os.path.basename(s)} in Sources */,")
A(f"\t\t); runOnlyForDeploymentPostprocessing = 0; }};")
A("/* End PBXSourcesBuildPhase section */")
A("")
A("/* Begin XCBuildConfiguration section */")
A(f"\t\t{projBuildConfig} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ABRPlayerDemo/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 16.0; LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\"; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.abrplayer.demo; PRODUCT_NAME = \"$(TARGET_NAME)\"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = \"1,2\"; }}; name = Debug; }};")
A(f"\t\t{uid(121)} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ABRPlayerDemo/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 16.0; LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\"; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.abrplayer.demo; PRODUCT_NAME = \"$(TARGET_NAME)\"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = \"1,2\"; }}; name = Release; }};")
A(f"\t\t{targetBuildConfig} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ABRPlayerDemo/Info.plist; CODE_SIGNING_ALLOWED = NO; IPHONEOS_DEPLOYMENT_TARGET = 16.0; LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\"; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.abrplayer.demo; PRODUCT_NAME = \"$(TARGET_NAME)\"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\"; SWIFT_EMIT_LOC_STRINGS = YES; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = \"1,2\"; }}; name = Debug; }};")
A(f"\t\t{uid(122)} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ABRPlayerDemo/Info.plist; CODE_SIGNING_ALLOWED = NO; IPHONEOS_DEPLOYMENT_TARGET = 16.0; LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\"; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.abrplayer.demo; PRODUCT_NAME = \"$(TARGET_NAME)\"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\"; SWIFT_EMIT_LOC_STRINGS = YES; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = \"1,2\"; }}; name = Release; }};")
A("/* End XCBuildConfiguration section */")
A("")
A("/* Begin XCConfigurationList section */")
A(f"\t\t{XCConfigurationList} /* Build configuration list for PBXProject */ = {{isa = XCConfigurationList; buildConfigurations = (")
A(f"\t\t\t{projBuildConfig} /* Debug */,")
A(f"\t\t\t{uid(121)} /* Release */,")
A(f"\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
A(f"\t\t{XCConfigurationList2} /* Build configuration list for PBXNativeTarget */ = {{isa = XCConfigurationList; buildConfigurations = (")
A(f"\t\t\t{targetBuildConfig} /* Debug */,")
A(f"\t\t\t{uid(122)} /* Release */,")
A(f"\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
A("/* End XCConfigurationList section */")
A("\t};")
A("\trootObject = " + PBXProject + " /* Project object */;")
A("}")

content = "\n".join(lines) + "\n"
out = os.path.join(ROOT, "ABRPlayerDemo.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    f.write(content)
print("Wrote", out, len(content), "bytes")
