#!/bin/sh
# A copy of the project without the embedded watch app (VoiceReader-sim.xcodeproj, git-ignored), for simulator runs
# on a Mac without the watchOS simulator runtime: xcodebuild refuses a scheme that embeds a watch app otherwise.
set -e
cd "$(dirname "$0")"
rm -rf VoiceReader-sim.xcodeproj
mkdir VoiceReader-sim.xcodeproj
cp VoiceReader.xcodeproj/project.pbxproj VoiceReader-sim.xcodeproj/
cp -R VoiceReader.xcodeproj/project.xcworkspace VoiceReader-sim.xcodeproj/ 2>/dev/null || true
sed -i '' -e '/F0A00000000000000000C020 \/\* Embed Watch Content \*\/,$/d' -e '/F0A00000000000000000C030 \/\* PBXTargetDependency \*\/,$/d' VoiceReader-sim.xcodeproj/project.pbxproj
