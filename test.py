#!/usr/bin/env python
#

import sys
try:
	from Foundation import NSDictionary
	z = NSDictionary.dictionaryWithContentsOfFile_("packages.plist")
except:
	from pbPlist import pbPlist
	z = pbPlist.PBPlist("packages.plist")

#print(type(z["packages"]))
packageDict = z["packages"]
for packageType in packageDict.keys():
	packages = packageDict[packageType]
	for package in packages:
		if not (package.get("title", None) or package.get("titles", None)):
			print(f"missing title in {package}")
		if not package.get("url", None):
			print(f"missing url in {package}")
		if not package.get("path", None) and packageType == "plugins":
			print(f"missing path in {package}")
