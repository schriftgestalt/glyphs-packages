from Foundation import NSDictionary

packages = NSDictionary.dictionaryWithContentsOfFile_("packages.plist")

if len(packages) > 10:
	exit 0
else:
	exit -1
