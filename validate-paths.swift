#!/usr/bin/env swift
import Foundation

guard let data = NSDictionary(contentsOfFile: "packages.plist"),
      let packages = data["packages"] as? NSDictionary else {
	print("Failed to read packages.plist")
	exit(2)
}

struct PathEntry {
	let path: String
	let minVersion: Int?
	let maxVersion: Int?
	let title: String
	let url: String

	func rangesOverlap(with other: PathEntry) -> Bool {
		let minV = self.minVersion ?? 0
		let maxV = self.maxVersion ?? Int.max
		let otherMinV = other.minVersion ?? 0
		let otherMaxV = other.maxVersion ?? Int.max
		return !(maxV < otherMinV || otherMaxV < minV)
	}
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
	} else if let singleTitle = plugin["title"] as? String {
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

	let entry = PathEntry(
		path: path,
		minVersion: minVersion,
		maxVersion: maxVersion,
		title: title,
		url: url)

	pathEntries[path, default: []].append(entry)
}

var conflicts: [(String, [PathEntry])] = []

for (path, entries) in pathEntries {
	if entries.count > 1 {
		// Check for overlapping version ranges
		for i in 0..<entries.count {
			for j in (i + 1)..<entries.count {
				if entries[i].rangesOverlap(with: entries[j]) {
					conflicts.append((path, [entries[i], entries[j]]))
				}
			}
		}
	}
}

for (path, entries) in conflicts {
	print("Path conflict: \(path)")
	
	for entry in entries {
		let versionStr: String
		if let minV = entry.minVersion, let maxV = entry.maxVersion {
			versionStr = " (versions \(minV)-\(maxV))"
		}
		else if let minV = entry.minVersion {
			versionStr = " (minVersion: \(minV))"
		}
		else if let maxV = entry.maxVersion {
			versionStr = " (maxVersion: \(maxV))"
		}
		else {
			versionStr = " (no version constraints)"
		}
		print("  - \(entry.title)\(versionStr) [\(entry.url)]")
	}
}

if hasError || !conflicts.isEmpty {
	exit(1)
}

print("All plugin paths are valid")
exit(0)
