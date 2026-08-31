// swift-tools-version:6.1
import PackageDescription

// Vendored from https://github.com/sindresorhus/KeyboardShortcuts at 1aef855, with one patch:
// Utilities.swift's `.localized` no longer uses the SwiftPM-generated `Bundle.module`, whose
// accessor only ever finds its resource bundle at the executable's own build path or at the
// root of an app bundle — neither of which exists once Copiste is signed and packaged as a
// real .app (macOS's codesign rejects loose files at the app bundle root outright). See
// docs/SPEC.md and Sources/Copiste/MenuIcon.swift for the same problem solved for our own
// resources.
let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(
			name: "KeyboardShortcuts",
			targets: [
				"KeyboardShortcuts"
			]
		)
	],
	targets: [
		.target(
			name: "KeyboardShortcuts",
			swiftSettings: [
				.swiftLanguageMode(.v5)
			]
		)
	]
)
