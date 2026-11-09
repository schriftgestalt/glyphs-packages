#!/usr/bin/env swift
import Foundation

let legacyInstallNameExceptions = ["rotateview"]

guard let data = NSDictionary(contentsOfFile: "packages.plist"),
      let packages = data["packages"] as? NSDictionary else {
	print("Failed to read packages.plist")
	exit(2)
}

struct VersionRange {
	let min: [Int]?
	let max: [Int]?
	
	var description: String {
		if let min, let max {
			return "\(formatVersion(min))-\(formatVersion(max))"
		}
		else if let min {
			return ">= \(formatVersion(min))"
		}
		else if let max {
			return "<= \(formatVersion(max))"
		}
		return "no version constraints"
	}
	
	func overlaps(with other: VersionRange) -> Bool {
		// Bounds are inclusive; a missing bound is unbounded.
		if let max, let otherMin = other.min, compareVersions(max, otherMin) < 0 {
			return false
		}
		if let otherMax = other.max, let min, compareVersions(otherMax, min) < 0 {
			return false
		}
		return true
	}
}

struct VersionConstraints {
	let buildNumber: VersionRange?
	let glyphsVersion: VersionRange?
	let systemVersion: VersionRange?
	
	var description: String {
		let ranges = [("build", buildNumber), ("Glyphs", glyphsVersion), ("macOS", systemVersion)]
		let descriptions = ranges.compactMap { name, range in
			range.map { "\(name): \($0.description)" }
		}
		return descriptions.isEmpty ? "no version constraints" : descriptions.joined(separator: ", ")
	}
	
	func overlaps(with other: VersionConstraints) -> Bool? {
		let inputs = [
			(self.buildNumber, other.buildNumber),
			(self.glyphsVersion, other.glyphsVersion),
			(self.systemVersion, other.systemVersion),
		]
		
		for (range, otherRange) in inputs {
			if let range, let otherRange, !range.overlaps(with: otherRange) {
				return false
			}
		}
		
		let hasGlyphsConstraint = self.buildNumber != nil || self.glyphsVersion != nil
		let otherHasGlyphsConstraint = other.buildNumber != nil || other.glyphsVersion != nil
		let sharesGlyphsConstraint = (buildNumber != nil && other.buildNumber != nil)
			|| (self.glyphsVersion != nil && other.glyphsVersion != nil)
		
		if hasGlyphsConstraint && otherHasGlyphsConstraint && !sharesGlyphsConstraint {
			return nil
		}
		else {
			return true
		}
	}
}

struct PackageEntry {
	let packageType: String
	let title: String
	let url: String
	let versions: VersionConstraints
	
	var versionDescription: String {
		self.versions.description
	}
	
	/// Returns `true` if ranges overlap, `false` if they do not, and `nil` if their types differ.
	func overlaps(with other: PackageEntry) -> Bool? {
		self.versions.overlaps(with: other.versions)
	}
}

func formatVersion(_ version: [Int]) -> String {
	version.map { String($0) }.joined(separator: ".")
}

func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
	let maxLength = max(a.count, b.count)
	for i in 0 ..< maxLength {
		let aValue = i < a.count ? a[i] : 0
		let bValue = i < b.count ? b[i] : 0
		if aValue < bValue { return -1 }
		if aValue > bValue { return 1 }
	}
	return 0
}

func parseVersionString(_ string: String) -> [Int]? {
	let components = string.split(separator: ".", omittingEmptySubsequences: false)
	var version: [Int] = []
	
	for component in components {
		guard !component.isEmpty,
		      component.allSatisfy({ $0 >= "0" && $0 <= "9" }),
		      let number = Int(component) else {
			return nil
		}
		version.append(number)
	}
	
	return version.isEmpty ? nil : version
}

struct VersionValidationError: Error, CustomStringConvertible {
	let description: String
}

func versionRange(
	for package: NSDictionary,
	minKey: String,
	maxKey: String,
	buildNumber: Bool,
) throws -> VersionRange? {
	func parseBound(_ key: String) throws -> [Int]? {
		guard let value = package[key] else {
			return nil
		}
		let string = (value as? String) ?? (buildNumber ? (value as? Int).map { String($0) } : nil)
		guard let string, let version = parseVersionString(string),
		      !buildNumber || version.count == 1 else {
			throw VersionValidationError(description: "invalid \(key): \(value)")
		}
		return version
	}
	
	let min = try parseBound(minKey)
	let max = try parseBound(maxKey)
	
	if let min, let max, compareVersions(min, max) > 0 {
		throw VersionValidationError(description: "\(minKey) exceeds \(maxKey)")
	}
	
	return min == nil && max == nil ? nil : VersionRange(min: min, max: max)
}

func versionConstraints(for package: NSDictionary) throws -> VersionConstraints {
	try VersionConstraints(
		buildNumber: versionRange(for: package, minKey: "minVersion", maxKey: "maxVersion", buildNumber: true),
		glyphsVersion: versionRange(for: package, minKey: "minGlyphsVersion", maxKey: "maxGlyphsVersion", buildNumber: false),
		systemVersion: versionRange(for: package, minKey: "minSystemVersion", maxKey: "maxSystemVersion", buildNumber: false))
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
		
		let versions: VersionConstraints; do {
			versions = try versionConstraints(for: package)
		}
		catch {
			print("Invalid version range: \(title ?? "untitled package") [\(url)]: \(error)")
			hasError = true
			continue
		}
		
		let entry = PackageEntry(
			packageType: packageType,
			title: title ?? "untitled package",
			url: url,
			versions: versions)
		
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
	for i in 0 ..< entries.count {
		for j in (i + 1) ..< entries.count {
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
	for i in 0 ..< entries.count {
		for j in (i + 1) ..< entries.count {
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
