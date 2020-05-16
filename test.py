#!/usr/bin/env python
#

import sys
from pbPlist import pbPlist

try:
	# purposely throwing away the return of PBPlist since we're just checking that it parses
	z = pbPlist.PBPlist("packages.plist")
except Exception as e:
	print(e)
	sys.exit(1)