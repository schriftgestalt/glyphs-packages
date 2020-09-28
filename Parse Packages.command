#!/bin/bash
cd "`dirname "$0"`"
pwd
echo
echo PARSING PACKAGES.PLIST...
plutil -lint packages.plist
echo
