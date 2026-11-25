// swift-tools-version:5.9
import Foundation
import PackageDescription

// A version tag resolves to the prebuilt XCFrameworks from that tag's GitHub release;
// `main` always builds from source. The release workflow fills this in on the tagged
// commit only, so it stays `nil` on every branch.
// Set PV_BUILD_FROM_SOURCE=1 to build a tagged version from source instead.
let binaryRelease: (version: String, checksums: [String: String])? = ("1.0.3", ["PVPatchEngine": "199fb0b01b6780d5554b0774ca576d2d6a7e82c47c84f5f8e2cecd40fd03be46"])

let environment = ProcessInfo.processInfo.environment
let buildFromSource = binaryRelease == nil || environment["PV_BUILD_FROM_SOURCE"] != nil
// The release workflow builds the frameworks it publishes from dynamic products, one
// module at a time, and names the ones already built so later modules link them
// instead of compiling them in again.
let buildingRelease = environment["PV_XCFRAMEWORK_BUILD"] != nil
let libraryType: Product.Library.LibraryType? = buildingRelease ? .dynamic : nil
let prebuilt = Set((environment["PV_XCFRAMEWORK_PREBUILT"] ?? "").split(separator: " ").map(String.init))

let module: (Target) -> Target = { source in
    prebuilt.contains(source.name)
        ? .binaryTarget(name: source.name, path: ".xcframework-build/\(source.name).xcframework")
        : source
}
// A product made only of a prebuilt framework cannot ask for a linkage type.
let libraryTypeFor: (String) -> Product.Library.LibraryType? = { module in
    prebuilt.contains(module) ? nil : libraryType
}

let sourceTargets: [Target] = [
    // Vendored xdelta3 (Apache-2.0 branch release3_1_apl, reports 3.1.1) plus a small pv_ shim
    // that hides the xd3 types from Swift. Only the decoder is used; the encoder stays compiled
    // because xdelta3-fgk.h references encoder symbols and does not build with XD3_ENCODER=0.
    .target(
        name: "CXdelta3",
        exclude: ["LICENSE", "xdelta3-lzma.h"],
        cSettings: [
            .define("static_assert", to: "_Static_assert"),
            .define("XD3_USE_LARGEFILE64", to: "1"),
            .define("XD3_ENCODER", to: "1"),
            .define("XD3_DEBUG", to: "0"),
            .define("SECONDARY_DJW", to: "1"),
            .define("SECONDARY_FGK", to: "1"),
            .define("SECONDARY_LZMA", to: "0"),
            .define("SIZEOF_SIZE_T", to: "__SIZEOF_SIZE_T__"),
            .define("SIZEOF_UNSIGNED_INT", to: "__SIZEOF_INT__"),
            .define("SIZEOF_UNSIGNED_LONG", to: "__SIZEOF_LONG__"),
            .define("SIZEOF_UNSIGNED_LONG_LONG", to: "__SIZEOF_LONG_LONG__")
        ],
        linkerSettings: [
            .linkedLibrary("z")
        ]
    ),
    .target(
        name: "PVPatchEngine",
        dependencies: ["CXdelta3"]
    )
] + (buildingRelease ? [] : [
    .testTarget(
        name: "PVPatchEngineTests",
        dependencies: ["PVPatchEngine"],
        resources: [
            .copy("Fixtures")
        ]
    )
])

let binaryTargets: [Target] = binaryRelease.map { release in
    release.checksums.sorted { $0.key < $1.key }.map { module, checksum in
        .binaryTarget(
            name: module,
            url: "https://github.com/Provenance-Emu/PVPatchEngine/releases/download/\(release.version)/\(module).xcframework.zip",
            checksum: checksum
        )
    }
} ?? []

let package = Package(
    name: "PVPatchEngine",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
        // Its own slice in the released XCFramework: a Catalyst app cannot link the macOS one.
        .macCatalyst(.v17)
    ],
    // Product names are the same in both modes, so consumers never change.
    products: buildFromSource ? [
        .library(name: "PVPatchEngine", type: libraryTypeFor("PVPatchEngine"), targets: ["PVPatchEngine"])
    ] : [
        .library(name: "PVPatchEngine", targets: ["PVPatchEngine"])
    ],
    targets: buildFromSource ? sourceTargets : binaryTargets
)
