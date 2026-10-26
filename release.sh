#!/bin/zsh
# 배포용 DMG 를 만든다: 빌드 → 앱 공증·스테이플 → DMG 서명 → DMG 공증·스테이플 → dist/
#   NOTARY_PROFILE  notarytool 키체인 프로필 이름 (기본 mac-explorer-notary)
#   처음 한 번: xcrun notarytool store-credentials <이름> --apple-id <Apple ID> --team-id <팀 ID> --password <앱 암호>
set -e
setopt pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
PROFILE=${NOTARY_PROFILE:-mac-explorer-notary}
if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
  echo "공증 프로필 '$PROFILE' 을 쓸 수 없습니다(없거나 인터넷이 끊김)." >&2
  exit 1
fi
./build.sh --release
APP="build/Haemil Back.app"
ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -n 1)
codesign --verify --deep --strict "$APP"

# 앱을 먼저 공증·스테이플해야 DMG 에서 꺼낸 앱도 인터넷 없이 열린다.
ditto -c -k --keepParent "$APP" build/HaemilBack.zip
xcrun notarytool submit build/HaemilBack.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

rm -rf dist build/dmg
mkdir -p dist build/dmg
DMG=dist/HaemilBack-$VERSION.dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Haemil Back $VERSION" -srcfolder build/dmg -ov -format UDZO $DMG
codesign --force --timestamp -s "$ID" $DMG
xcrun notarytool submit $DMG --keychain-profile "$PROFILE" --wait
xcrun stapler staple $DMG
xcrun stapler validate $DMG
spctl -a -t open --context context:primary-signature -v $DMG
spctl -a -t exec -v "$APP"
# 사이트·GitHub 에서 늘 같은 주소로 받도록 버전 없는 이름도 둔다.
cp $DMG dist/HaemilBack.dmg
# shortcut: 옛 이름 BendBack.dmg 로도 한 벌 둔다(1.0.0 때 사이트가 묶인 고정 주소). 사이트가 HaemilBack.dmg 로 옮기면 지운다.
cp $DMG dist/BendBack.dmg
(cd dist && shasum -a 256 *.dmg > SHA256SUMS)
echo "배포 준비 완료:"; ls -la dist
