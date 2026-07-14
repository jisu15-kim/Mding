<p align="center">
  <img src="Mding/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Mding">
</p>

# Mding

내가 쓰려고 만든 마크다운 뷰어 및 에디터

## 설치

```bash
brew install --cask jisu15-kim/tap/mding
```

또는 [Releases](https://github.com/jisu15-kim/Mding/releases/latest)에서 DMG를 받아 설치합니다. (macOS 26.0+)

## 빌드

```bash
mise install                  # Tuist 설치
mise exec -- tuist install    # 의존성 해결
mise exec -- tuist generate   # Xcode 프로젝트 생성
mise exec -- tuist build      # 앱 빌드
```

테스트:

```bash
mise exec -- tuist test
```

Xcode에서 작업하려면 `tuist generate` 후 생성된 `Mding.xcworkspace`를 엽니다.
