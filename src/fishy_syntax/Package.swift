// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "FishySyntax",
  platforms: [.macOS(.v10_15)],
  products: [
    .executable(name: "fishy_syntax", targets: ["FishySyntax"])
  ],
  dependencies: [
    .package(path: "/Users/tristan/fishytool/swift-syntax")
  ],
  targets: [
    .executableTarget(
      name: "FishySyntax",
      dependencies: [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    )
  ]
)
