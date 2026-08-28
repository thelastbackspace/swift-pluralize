// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pluralize",
    products: [
        .library(name: "Pluralize", targets: ["Pluralize"])
    ],
    targets: [
        .target(name: "Pluralize"),
        .testTarget(name: "PluralizeTests", dependencies: ["Pluralize"]),
    ]
)
