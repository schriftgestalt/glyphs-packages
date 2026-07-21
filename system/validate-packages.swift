#!/usr/bin/env swift
import Foundation

let legacyInstallNameExceptions = ["rotateview"]

guard let data = NSDictionary(contentsOfFile: "packages.plist"),
      let packages = data["packages"] as? NSDictionary else {
	print("Failed to read packages.plist")
	exit(2)
}

enum VersionRange {
	case buildNumber(min: Int?, max: Int?)
	case glyphsVersion(min: [Int]?, max: [Int]?)

	var description: String {
		switch self {
		case .buildNumber(let min, let max):
			if let min, let max {
				return "versions \(min)-\(max)"
			}
			else if let min {
				return "minVersion: \(min)"
			}
			else if let max {
				return "maxVersion: \(max)"
			}
		case .glyphsVersion(let min, let max):
			if let min, let max {
				return "versions \(formatVersion(min))-\(formatVersion(max))"
			}
			else if let min {
				return "minGlyphsVersion: \(formatVersion(min))"
			}
			else if let max {
				return "maxGlyphsVersion: \(formatVersion(max))"
			}
		}
		return "no version constraints"
	}

	func overlaps(with other: VersionRange) -> Bool? {
		switch (self, other) {
		case (.buildNumber(let minA, let maxA), .buildNumber(let minB, let maxB)):
			let minV = minA ?? 0
			let maxV = maxA ?? Int.max
			let otherMinV = minB ?? 0
			let otherMaxV = maxB ?? Int.max
			return !(maxV < otherMinV || otherMaxV < minV)
		case (.glyphsVersion(let minA, let maxA), .glyphsVersion(let minB, let maxB)):
			let minG = minA ?? [0]
			let maxG = maxA ?? [Int.max]
			let otherMinG = minB ?? [0]
			let otherMaxG = maxB ?? [Int.max]
			return !(compareVersions(maxG, otherMinG) < 0 || compareVersions(otherMaxG, minG) < 0)
		default:
			return nil
		}
	}
}

struct PackageEntry {
	let packageType: String
	let title: String
	let url: String
	let versionRange: VersionRange?

	var versionDescription: String {
		versionRange?.description ?? "no version constraints"
	}

	/// Returns `true` if ranges overlap, `false` if they do not, and `nil` if their types differ.
	func overlaps(with other: PackageEntry) -> Bool? {
		guard let versionRange, let otherRange = other.versionRange else {
			return true
		}
		return versionRange.overlaps(with: otherRange)
	}
}

func formatVersion(_ version: [Int]) -> String {
	version.map { String($0) }.joined(separator: ".")
}

func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
	let maxLength = max(a.count, b.count)
	for i in 0..<maxLength {
		let aValue = i < a.count ? a[i] : 0
		let bValue = i < b.count ? b[i] : 0
		if aValue < bValue { return -1 }
		if aValue > bValue { return 1 }
	}
	return 0
}

func parseVersionString(_ string: String) -> [Int]? {
	let components = string.split(separator: ".").compactMap { Int($0) }
	return components.isEmpty ? nil : components
}

func versionRange(for package: NSDictionary) -> VersionRange? {
	let minVersion = (package["minVersion"] as? Int) ?? (package["minVersion"] as? String).flatMap(Int.init)
	let maxVersion = (package["maxVersion"] as? Int) ?? (package["maxVersion"] as? String).flatMap(Int.init)
	if minVersion != nil || maxVersion != nil {
		return .buildNumber(min: minVersion, max: maxVersion)
	}

	let minGlyphsVersion = (package["minGlyphsVersion"] as? String).flatMap(parseVersionString)
	let maxGlyphsVersion = (package["maxGlyphsVersion"] as? String).flatMap(parseVersionString)
	if minGlyphsVersion != nil || maxGlyphsVersion != nil {
		return .glyphsVersion(min: minGlyphsVersion, max: maxGlyphsVersion)
	}

	return nil
}

func packageTitle(_ package: NSDictionary) -> String? {
	if let titles = package["titles"] as? NSDictionary, let title = titles["en"] as? String {
		return title
	}
	return package["title"] as? String
}

func conflictReason(for entryA: PackageEntry, and entryB: PackageEntry) -> String? {
	switch entryA.overlaps(with: entryB) {
	case nil:
		return "incompatible version types"
	case true?:
		return "overlapping version ranges"
	case false?:
		return nil
	}
}

var pathEntries: [String: [PackageEntry]] = [:]
var installNameEntries: [String: [PackageEntry]] = [:]
var hasError = false

for packageType in ["plugins", "scripts", "modules"] {
	guard let packageList = packages[packageType] as? [NSDictionary] else {
		continue
	}

	for package in packageList {
		guard let url = package["url"] as? String else {
			print("Package missing url: \(package)")
			hasError = true
			continue
		}

		let title = packageTitle(package)
		let entry = PackageEntry(
			packageType: packageType,
			title: title ?? "untitled package",
			url: url,
			versionRange: versionRange(for: package))

		let installName = (package["installName"] as? String) ?? URL(string: url)?.lastPathComponent
		if let installName {
			installNameEntries[installName.lowercased(), default: []].append(entry)
		}
		else {
			print("Package missing install name and url")
			hasError = true
		}

		guard packageType == "plugins" else {
			continue
		}

		guard let path = package["path"] as? String else {
			print("Plugin missing path: \(package)")
			hasError = true
			continue
		}
		guard title != nil else {
			print("Plugin missing title: \(package)")
			hasError = true
			continue
		}
		pathEntries[path, default: []].append(entry)
	}
}

var hasConflicts = false

for (path, entries) in pathEntries {
	for i in 0..<entries.count {
		for j in (i + 1)..<entries.count {
			let entryA = entries[i]
			let entryB = entries[j]
			guard let reason = conflictReason(for: entryA, and: entryB) else {
				continue
			}

			hasConflicts = true
			print("Path conflict (\(reason)): \(path)")
			for entry in [entryA, entryB] {
				print("  - \(entry.title) (\(entry.versionDescription)) [\(entry.url)]")
			}
		}
	}
}

for (installName, entries) in installNameEntries where !legacyInstallNameExceptions.contains(installName) {
	for i in 0..<entries.count {
		for j in (i + 1)..<entries.count {
			let entryA = entries[i]
			let entryB = entries[j]

			// Entries from one repository install into the same directory.
			guard entryA.url != entryB.url,
				  let reason = conflictReason(for: entryA, and: entryB) else {
				continue
			}

			hasConflicts = true
			print("Duplicate install name (\(reason)): \(installName)")
			for entry in [entryA, entryB] {
				print("  - \(entry.title) [\(entry.packageType), \(entry.versionDescription)] \(entry.url)")
			}
		}
	}
}

if hasError || hasConflicts {
	exit(1)
}

print("All package paths and install names are valid")
exit(0)
