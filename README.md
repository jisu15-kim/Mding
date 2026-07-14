# Mding

내가 쓰려고 만든 마크다운 뷰어 및 에디터

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
