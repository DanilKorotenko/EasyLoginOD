#!/bin/bash

BUILT_PRODUCTS_DIR="$1"
WRAPPER_NAME="$2"
COMMAND_NAME="$3"

SRC_MODULE="$BUILT_PRODUCTS_DIR/$WRAPPER_NAME"

SETUP_TOOL="/Library/OpenDirectory/Modules/$WRAPPER_NAME/Contents/MacOS/$COMMAND_NAME"

logger "Last time deployModuleForDebug.sh was run was for $1, $2, $3"

### Check if source is a real XPC bundle
BundlePackageType=$(/usr/libexec/PlistBuddy -c "print CFBundlePackageType" "$SRC_MODULE/Contents/Info.plist")

if [ "$BundlePackageType" != "XPC!" ]
then
    echo "Unsuported package type"
    exit 1
fi

### Check if configuration tool already exist
### If so, ensure pre-existing module is unloaded and reboot opendirectoryd
if [ -f "$SETUP_TOOL" ]
then
    "$SETUP_TOOL" unset
    killall opendirectoryd
fi

cp -R "$SRC_MODULE" /Library/OpenDirectory/Modules/

"$SETUP_TOOL" set
killall opendirectoryd

exit 0
