#!/bin/zsh
# back.bend 를 인텔·애플실리콘 겸용 "build/Haemil Back.app" 으로 빌드하고 서명한다.
#   ./build.sh            개발용: 키체인에 Developer ID 가 있으면 그것으로, 없으면 임시 서명
#   ./build.sh --release  배포용: Developer ID 필수, 보안 타임스탬프 포함
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
RELEASE=$([[ "$1" == "--release" ]] && echo 1 || echo 0)
mkdir -p build
~/.bend/bin/bend back.bend -o build/back.c
# bend 가 맥에서 쓰는 옵션과 같다(side.c 의 #import 때문에 Objective-C, -fmodules 가 프레임워크를 링크). 아키텍처만 둘로 나눠 빌드한다.
for arch in arm64 x86_64; do
  clang -x objective-c -fobjc-arc -fmodules -std=c11 -O3 -w -arch $arch -mmacosx-version-min=13.0 \
    build/back.c -lpthread -lm -o build/back-$arch
done
APP="build/Haemil Back.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/back-arm64 build/back-x86_64 -output "$APP/Contents/MacOS/haemil-back"
cp AppIcon.icns LICENSE NOTICE "$APP/Contents/Resources/"
# 해밀 탐색기와 같은 꼴: 기본 이름은 영어, 한국어 환경에서는 "해밀 Back"
for lang in ko en ja; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
  NAME=$([[ $lang == ko ]] && echo "해밀 Back" || echo "Haemil Back")
  printf '"CFBundleName" = "%s";\n"CFBundleDisplayName" = "%s";\n' "$NAME" "$NAME" > "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
done
# 번들 id 는 lab.bend.back 그대로: 바꾸면 이미 설치한 사람이 손쉬운 사용 권한을 다시 줘야 한다.
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>lab.bend.back</string>
<key>CFBundleName</key><string>Haemil Back</string>
<key>CFBundleDisplayName</key><string>Haemil Back</string>
<key>CFBundleExecutable</key><string>haemil-back</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>ko</string>
<key>LSHasLocalizedDisplayName</key><true/>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Kwangsub Shin. MIT License.</string>
</dict></plist>
PL
ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -n 1)
if [[ -n "$ID" ]]; then
  codesign --force --options runtime $([[ $RELEASE == 1 ]] && echo --timestamp || echo --timestamp=none) -s "$ID" "$APP"
elif [[ $RELEASE == 1 ]]; then
  echo "배포용 빌드에는 키체인의 Developer ID Application 인증서가 필요합니다" >&2
  exit 1
else
  echo "경고: Developer ID 가 없어 임시 서명합니다. 다시 빌드할 때마다 손쉬운 사용 권한을 다시 줘야 합니다." >&2
  codesign --force -s - "$APP"
fi
echo "빌드 완료: $PWD/$APP ($VERSION)"
