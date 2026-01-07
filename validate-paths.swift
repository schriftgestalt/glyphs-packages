#!/usr/bin/env swift
import Foundation

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
				return "versions \(self.formatVersion(min))-\(self.formatVersion(max))"
			}
			else if let min {
				return "minGlyphsVersion: \(self.formatVersion(min))"
			}
			else if let max {
				return "maxGlyphsVersion: \(self.formatVersion(max))"
			}
		}
		return "no version constraints"
	}

	private func formatVersion(_ v: [Int]) -> String {
		v.map { String($0) }.joined(separator: ".")
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

	private func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
		let maxLen = max(a.count, b.count)
		for i in 0..<maxLen {
			let aVal = i < a.count ? a[i] : 0
			let bVal = i < b.count ? b[i] : 0
			if aVal < bVal { return -1 }
			if aVal > bVal { return 1 }
		}
		return 0
	}
}

struct PathEntry {
	let path: String
	let versionRange: VersionRange?
	let title: String
	let url: String

	var versionDescription: String {
		versionRange?.description ?? "no version constraints"
	}

	/// Returns `true` if ranges overlap, `false` if they don't, `nil` if incompatible types
	func overlaps(with other: PathEntry) -> Bool? {
		guard let range = versionRange, let otherRange = other.versionRange else {
			// If either has no constraints, they overlap
			return true
		}
		return range.overlaps(with: otherRange)
	}
}

func parseVersionString(_ str: String) -> [Int]? {
	let components = str.split(separator: ".").compactMap { Int($0) }
	return components.isEmpty ? nil : components
}

var pathEntries: [String: [PathEntry]] = [:]
var hasError = false

guard let pluginList = packages["plugins"] as? [NSDictionary] else {
	print("No plugins found in packages.plist")
	exit(0)
}

for plugin in pluginList {
	guard let path = plugin["path"] as? String else {
		print("Plugin missing path: \(plugin)")
		hasError = true
		continue
	}

	var title: String?
	if let titleDict = plugin["titles"] as? NSDictionary {
		title = titleDict["en"] as? String
	}
	else if let singleTitle = plugin["title"] as? String {
		title = singleTitle
	}

	guard let title = title else {
		print("Plugin missing title: \(plugin)")
		hasError = true
		continue
	}

	guard let url = plugin["url"] as? String else {
		print("Plugin missing url: \(plugin)")
		hasError = true
		continue
	}

	// Parse version range
	var versionRange: VersionRange? = nil

	// Check for build number versions (minVersion/maxVersion)
	var minVersion: Int? = nil
	if let intVal = plugin["minVersion"] as? Int {
		minVersion = intVal
	}
	else if let strVal = plugin["minVersion"] as? String, let intVal = Int(strVal) {
		minVersion = intVal
	}

	var maxVersion: Int? = nil
	if let intVal = plugin["maxVersion"] as? Int {
		maxVersion = intVal
	}
	else if let strVal = plugin["maxVersion"] as? String, let intVal = Int(strVal) {
		maxVersion = intVal
	}

	if minVersion != nil || maxVersion != nil {
		versionRange = .buildNumber(min: minVersion, max: maxVersion)
	}
	else {
		// Check for Glyphs version strings (minGlyphsVersion/maxGlyphsVersion)
		var minGlyphsVersion: [Int]? = nil
		if let strVal = plugin["minGlyphsVersion"] as? String {
			minGlyphsVersion = parseVersionString(strVal)
		}

		var maxGlyphsVersion: [Int]? = nil
		if let strVal = plugin["maxGlyphsVersion"] as? String {
			maxGlyphsVersion = parseVersionString(strVal)
		}

		if minGlyphsVersion != nil || maxGlyphsVersion != nil {
			versionRange = .glyphsVersion(min: minGlyphsVersion, max: maxGlyphsVersion)
		}
	}

	let entry = PathEntry(
		path: path,
		versionRange: versionRange,
		title: title,
		url: url)

	pathEntries[path, default: []].append(entry)
}

var conflicts: [(String, [PathEntry], String)] = []  // (path, entries, reason)

for (path, entries) in pathEntries {
	if entries.count > 1 {
		for i in 0..<entries.count {
			for j in (i + 1)..<entries.count {
				let entryA = entries[i]
				let entryB = entries[j]
				
				switch entryA.overlaps(with: entryB) {
				case nil:
					conflicts.append((path, [entryA, entryB], "incompatible version types"))
				case true?:
					conflicts.append((path, [entryA, entryB], "overlapping version ranges"))
				case false?:
					break
				}
			}
		}
	}
}

for (path, entries, reason) in conflicts {
	print("Path conflict (\(reason)): \(path)")
	for entry in entries {
		print("  - \(entry.title) (\(entry.versionDescription)) [\(entry.url)]")
	}
}

if hasError || !conflicts.isEmpty {
	exit(1)
}

print("All plugin paths are valid")
exit(0)
