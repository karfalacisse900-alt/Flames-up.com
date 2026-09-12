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
    .package(url: "https://github.com/google/GoogleSignIn-iOS.git", exact: "9.1.0"),
    .package(url: "https://github.com/stripe/stripe-ios.git", exact: "26.9.0")
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
        .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
        .product(name: "StripePaymentSheet", package: "stripe-ios"),
        .product(name: "StripePayments", package: "stripe-ios")
      ]
    ),
    .testTarget(
      name: "MIRANativeTests",
      dependencies: ["MIRANative"]
    )
  ],
  cxxLanguageStandard: .cxx17
)
