#!/usr/bin/env swift
import Foundation

let legacyExceptions = ["rotateview"]

guard let data = NSDictionary(contentsOfFile: "packages.plist"),
      let packages = data["packages"] as? NSDictionary else {
	print("Failed to read packages.plist")
	exit(2)
}

var names: [String: String] = [:]
var duplicates: [String] = []
var hasError = false

for pkgType in ["plugins", "scripts", "modules"] {
	guard let pkgList = packages[pkgType] as? [NSDictionary] else {
		continue
	}

	for pkg in pkgList {
		var name: String?

		guard let urlString = pkg["url"] as? String else {
			print("Package missing url: \(pkg)")
			hasError = true
			continue
		}

		if let installName = pkg["installName"] as? String {
			name = installName
		}
		else if let url = URL(string: urlString) {
			name = url.lastPathComponent
		}

		guard let name else {
			print("Package missing install name and url")
			hasError = true
			continue
		}

		let nameLower = name.lowercased()
		if let existingURL = names[nameLower], existingURL != urlString {
			if !legacyExceptions.contains(nameLower) {
				duplicates.append(name)
			}
		}
		names[nameLower] = urlString
	}
}

for duplicate in duplicates {
	print("Duplicate install name: \(duplicate)")
}

if hasError || !duplicates.isEmpty {
	exit(1)
}

print("All install names are unique")
exit(0)
