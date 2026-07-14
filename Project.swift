import ProjectDescription

let project = Project(
    name: "Mding",
    settings: .settings(base: [
        "MARKETING_VERSION": "1.0.4",
        "CURRENT_PROJECT_VERSION": "5",
        "DEVELOPMENT_TEAM": "846TMZL7WC",
        // 공증(notarization) 필수 조건 — 모든 타깃에 적용.
        "ENABLE_HARDENED_RUNTIME": "YES",
    ]),
    targets: [
        .target(
            name: "Mding",
            destinations: .macOS,
            product: .app,
            bundleId: "com.jisukim.Mding",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // Sparkle 자동 업데이트 — appcast 는 main 브랜치 raw URL 에서 서빙.
                "SUFeedURL": "https://raw.githubusercontent.com/jisu15-kim/Mding/main/appcast.xml",
                "SUPublicEDKey": "Hx7FBLN+dosEOzHhCvBrM16cjsaDQlLdjmkbmNZKAeQ=",
                "CFBundleDocumentTypes": [[
                    "CFBundleTypeName": "Markdown Document",
                    "CFBundleTypeRole": "Editor",
                    "LSHandlerRank": "Alternate",
                    "LSItemContentTypes": ["net.daringfireball.markdown"],
                ]],
                "UTImportedTypeDeclarations": [[
                    "UTTypeIdentifier": "net.daringfireball.markdown",
                    "UTTypeConformsTo": ["public.plain-text"],
                    "UTTypeDescription": "Markdown Document",
                    "UTTypeTagSpecification": ["public.filename-extension": ["md", "markdown", "mdown"]],
                ]],
            ]),
            sources: ["Mding/Sources/**"],
            resources: [
                // Preview 셸은 상대 경로(js/, css/)를 보존해야 하므로 folder reference 로 번들한다.
                .glob(pattern: "Mding/Resources/**", excluding: ["Mding/Resources/Preview/**"]),
                .folderReference(path: "Mding/Resources/Preview"),
            ],
            // 앱이 appex 에 의존하면 Tuist 가 PlugIns/ 에 자동 임베드한다.
            dependencies: [
                .target(name: "MdingQuickLook"),
                .external(name: "Sparkle"),
            ]
        ),
        .target(
            name: "MdingQuickLook",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "com.jisukim.Mding.QuickLookPreview",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleDisplayName": "Mding Markdown Preview",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.quicklook.preview",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).PreviewProvider",
                    "NSExtensionAttributes": [
                        // data-based 프리뷰: 정적 HTML 반환, QL 쪽에서 JS 실행 없음.
                        "QLIsDataBasedPreview": true,
                        "QLSupportedContentTypes": ["net.daringfireball.markdown"],
                    ],
                ],
            ]),
            sources: [
                "MdingQuickLook/Sources/**",
                // JSC 렌더러는 앱 타깃(Mding/Sources glob)과 공유 — 유닛 테스트는 MdingTests 가 담당.
                "Mding/Sources/Services/MarkdownHTMLRenderer.swift",
            ],
            resources: [
                // 앱과 동일한 프리뷰 에셋(js/css) 재사용 — 상대 경로 보존 위해 folder reference.
                .folderReference(path: "Mding/Resources/Preview"),
            ],
            // appex 는 샌드박스 필수 (메인 앱은 non-sandbox 방침 유지 — AGENTS.md §0.6).
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
            ]),
            dependencies: []
        ),
        .target(
            name: "MdingTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.jisukim.MdingTests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["Mding/Tests/**"],
            resources: [],
            dependencies: [.target(name: "Mding")]
        ),
    ]
)
