// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "Mding",
    dependencies: [
        // 자동 업데이트 (배포판 전용 — appcast 는 GitHub raw 에서 서빙)
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // 분석/크래시 리포트 (macOS 지원 — Analytics·Crashlytics 만 사용)
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0"),
    ]
)
