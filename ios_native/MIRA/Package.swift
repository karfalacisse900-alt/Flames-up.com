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
  targets: [
    .target(
      name: "MIRACoreCpp",
      publicHeadersPath: "include"
    ),
    .target(
      name: "MIRANative",
      dependencies: ["MIRACoreCpp"]
    )
  ],
  cxxLanguageStandard: .cxx17
)
