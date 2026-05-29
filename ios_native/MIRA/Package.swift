// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MIRANative",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    .library(name: "MIRANative", targets: ["MIRANative"]),
    .library(name: "MIRACoreCpp", targets: ["MIRACoreCpp"])
  ],
  dependencies: [
    .package(url: "https://github.com/AgoraIO/AgoraRtcEngine_iOS.git", exact: "4.6.2"),
    .package(url: "https://github.com/google/GoogleSignIn-iOS.git", exact: "9.1.0")
  ],
  targets: [
    .target(
      name: "MIRACoreCpp",
      publicHeadersPath: "include"
    ),
    .target(
      name: "MIRANative",
      dependencies: [
        "MIRACoreCpp",
        .product(name: "RtcBasic", package: "AgoraRtcEngine_iOS"),
        .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
      ]
    )
  ],
  cxxLanguageStandard: .cxx17
)
