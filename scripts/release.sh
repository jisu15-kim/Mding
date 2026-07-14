#!/usr/bin/env bash
# Mding 릴리스 파이프라인
#   빌드 → Developer ID 서명 → DMG → 공증(notarization) → 스테이플 → GitHub Release → appcast 갱신
#
# 선행 조건 (최초 1회):
#   1. Xcode 에 Developer ID Application 인증서 발급
#   2. 공증 자격증명을 키체인 프로필로 저장:
#        xcrun notarytool store-credentials mding-notary \
#          --apple-id <애플개발자계정이메일> --team-id 846TMZL7WC
#      (암호는 https://account.apple.com ▸ 로그인 및 보안 ▸ 앱 암호 에서 생성한 앱 암호)
#   3. gh auth login (GitHub Release 생성용)
#
# 릴리스 절차:
#   1. Project.swift 의 MARKETING_VERSION (예: 1.1.0) 과
#      CURRENT_PROJECT_VERSION (정수, 릴리스마다 +1 — Sparkle 버전 비교 기준) 을 올리고 커밋
#   2. make release  (또는 ./scripts/release.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

REPO="jisu15-kim/Mding"
SCHEME="Mding"
SIGN_IDENTITY="Developer ID Application: Jisu Kim (846TMZL7WC)"
NOTARY_PROFILE="${NOTARY_PROFILE:-mding-notary}"
SPARKLE_BIN="$REPO_ROOT/.tools/sparkle/bin"
RELEASE_DIR="$REPO_ROOT/.release"

VERSION=$(sed -n 's/.*"MARKETING_VERSION": "\([^"]*\)".*/\1/p' Project.swift)
BUILD_NUM=$(sed -n 's/.*"CURRENT_PROJECT_VERSION": "\([^"]*\)".*/\1/p' Project.swift)
[[ -n "$VERSION" && -n "$BUILD_NUM" ]] || { echo "✗ Project.swift 에서 버전을 읽지 못했습니다"; exit 1; }

TAG="v$VERSION"
DMG="$RELEASE_DIR/Mding-$VERSION.dmg"

echo "▸ Mding $VERSION (build $BUILD_NUM) 릴리스 시작"

# 0) 사전 점검 --------------------------------------------------------------
[[ -z "$(git status --porcelain)" ]] \
    || { echo "✗ 작업 트리가 clean 하지 않습니다. 커밋 후 다시 실행하세요."; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    && { echo "✗ 태그 $TAG 가 이미 존재합니다. MARKETING_VERSION 을 올리세요."; exit 1; }
if [[ -f appcast.xml ]] && grep -q "sparkle:version=\"$BUILD_NUM\"" appcast.xml; then
    echo "✗ build $BUILD_NUM 이 이미 appcast 에 있습니다. CURRENT_PROJECT_VERSION 을 올리세요."
    exit 1
fi
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || { echo "✗ 공증 프로필 '$NOTARY_PROFILE' 없음 — 파일 상단의 store-credentials 명령을 먼저 실행하세요."; exit 1; }

# Sparkle CLI 도구(appcast 생성·서명) — 없으면 최신 릴리스에서 다운로드
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "▸ Sparkle CLI 도구 다운로드"
    SPARKLE_TAG=$(curl -sL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
        | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)
    mkdir -p "$REPO_ROOT/.tools/sparkle"
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TAG/Sparkle-$SPARKLE_TAG.tar.xz" \
        | tar -xJ -C "$REPO_ROOT/.tools/sparkle" bin
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 1) 빌드 → 아카이브 ---------------------------------------------------------
echo "▸ tuist generate + Release 아카이브 (수 분 소요)"
mise exec -- tuist install
mise exec -- tuist generate --no-open
xcodebuild -workspace Mding.xcworkspace -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$RELEASE_DIR/Mding.xcarchive" archive \
    >"$RELEASE_DIR/archive.log" 2>&1 \
    || { tail -30 "$RELEASE_DIR/archive.log"; exit 1; }

# 2) Developer ID 서명으로 내보내기 -------------------------------------------
echo "▸ Developer ID export"
xcodebuild -exportArchive \
    -archivePath "$RELEASE_DIR/Mding.xcarchive" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$RELEASE_DIR/export" \
    >"$RELEASE_DIR/export.log" 2>&1 \
    || { tail -30 "$RELEASE_DIR/export.log"; exit 1; }
APP="$RELEASE_DIR/export/Mding.app"
codesign --verify --deep --strict "$APP"

# 3) DMG 패키징 --------------------------------------------------------------
echo "▸ DMG 생성"
command -v create-dmg >/dev/null || brew install create-dmg
STAGE="$RELEASE_DIR/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
# 배경: 1x·2x PNG 를 멀티해상도 TIFF 로 합쳐 레티나 대응.
# 원본 PNG 는 scripts/generate_dmg_background.swift 로 생성·커밋되어 있다.
tiffutil -cathidpicheck scripts/dmg-assets/dmg-background.png scripts/dmg-assets/dmg-background@2x.png \
    -out "$RELEASE_DIR/dmg-background.tiff" 2>/dev/null
create-dmg \
    --volname "Mding $VERSION" \
    --volicon "$APP/Contents/Resources/AppIcon.icns" \
    --background "$RELEASE_DIR/dmg-background.tiff" \
    --window-pos 200 150 \
    --window-size 660 420 \
    --icon-size 128 \
    --text-size 13 \
    --icon "Mding.app" 165 190 \
    --hide-extension "Mding.app" \
    --app-drop-link 495 190 \
    "$DMG" "$STAGE"
# DMG 컨테이너도 서명해야 spctl(Gatekeeper) 평가를 통과한다.
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

# 4) 공증 + 스테이플 ----------------------------------------------------------
echo "▸ 공증 제출 (Apple 서버 대기, 수 분 소요)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature "$DMG"
echo "✓ 공증·스테이플 완료"

# 5) appcast 갱신 (Sparkle 자동 업데이트 피드) ---------------------------------
echo "▸ appcast.xml 갱신"
UPDATES="$RELEASE_DIR/updates"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    -o "$REPO_ROOT/appcast.xml" \
    "$UPDATES"

# 6) GitHub Release 게시 + appcast 푸시 ---------------------------------------
echo "▸ GitHub Release 게시"
gh release create "$TAG" "$DMG" --title "Mding $VERSION" --generate-notes
git add appcast.xml
git commit -m "release: $TAG"
git push origin main

# 7) Homebrew tap cask 갱신 ----------------------------------------------------
echo "▸ Homebrew tap cask 갱신"
TAP_REPO="jisu15-kim/homebrew-tap"
SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
CASK_FILE="$RELEASE_DIR/mding.rb"
cat >"$CASK_FILE" <<EOF
cask "mding" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/Mding-#{version}.dmg"
  name "Mding"
  desc "Lightweight native Markdown viewer and editor"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :tahoe

  app "Mding.app"

  zap trash: [
    "~/Library/Caches/com.jisukim.Mding",
    "~/Library/HTTPStorages/com.jisukim.Mding",
    "~/Library/Preferences/com.jisukim.Mding.plist",
    "~/Library/Saved Application State/com.jisukim.Mding.savedState",
    "~/Library/WebKit/com.jisukim.Mding",
  ]
end
EOF
EXISTING_SHA=$(gh api "repos/$TAP_REPO/contents/Casks/mding.rb" --jq .sha 2>/dev/null || true)
gh api -X PUT "repos/$TAP_REPO/contents/Casks/mding.rb" \
    -f message="mding $VERSION" \
    -f content="$(base64 -i "$CASK_FILE")" \
    ${EXISTING_SHA:+-f sha="$EXISTING_SHA"} >/dev/null
echo "✓ tap 갱신: https://github.com/$TAP_REPO"

echo ""
echo "✓ Mding $VERSION 릴리스 완료"
echo "  https://github.com/$REPO/releases/tag/$TAG"
