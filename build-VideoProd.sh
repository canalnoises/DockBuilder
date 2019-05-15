#!/bin/bash
#shellcheck disable=SC2088,SC2016

# Identifier for the .app and .pkg
identifier="org.ldschurch.psd.dockbuilder-VideoProd"

# Version of the .app and .pkg, you can leave this alone and specify at the command line
version="1.0"

# Path and filename of the main property list used to store preferences for the .app
preferenceFileFullPath="/Library/Preferences/org.ldschurch.psd.dockbuilder-VideoProd.defaults.plist"

# Path to the breadcrumb dropped when DockBuilder runs for a user, this should be in the user's home folder
# Note: You should keep this in single quotes and don't remove the $HOME environmental variable
breadcrumb='$HOME/Library/Preferences/org.ldschurch.psd.dockbuilder.breadcrumb.plist'

# Path to the DockBuilder log, this should be in the user's home folder
# Note: You should keep this in single quotes and don't remove the $HOME environmental variable
log='$HOME/Library/Logs/DockBuilder.log'

# The icon for the .app
appIcon="/System/Library/CoreServices/Dock.app/Contents/Resources/Dock.icns"

# Determines if the user's Dock is hidden while being built for the first time
hideDockWhileBuilding="true" # (true|false)

# If the above variable is set to true, the message below will be displayed
hideDockMessage="Please wait while the Dock is configured."

# Array to hold all the items we need to add
# Note: if you need to add options you must seperate the item from the options with a , (comma)
# Example: "/Applications/,--view grid --display stack --sort name"
# This will add the /Applications folder to the persistent-others section of the Dock and sets
# the view to grid, the display to stack, and sorts by name.
# All options available here: https://github.com/kcrawford/dockutil
defaultItemsToAdd=(
    "/Applications/Launchpad.app/"
    "/Applications/Mission Control.app/"
    "/Applications/PSD App Store.app/"
    "/Applications/Safari.app/"
    "/Applications/Microsoft Excel.app/"
    "/Applications/Microsoft OneNote.app/"
    "/Applications/Microsoft Outlook.app/"
    "/Applications/Microsoft PowerPoint.app/"
    "/Applications/Microsoft Word.app/"
    "/Applications/OneDrive.app/"
    "/Applications/Notes.app/"
    "/Applications/System Preferences.app/"
    "/Applications/,--view grid --display stack --sort name"
    "~/Downloads"
)

########### It is not necessary to edit beyond this poing, do at your own risk ###########

function install_dockutil_pkg () {
    if [[ -e /private/tmp/DockBuilder/files/usr/local/bin/dockutil ]]; then
        echo "dockutil binary has been installed in test build directory"
    else
        pkgutil --expand-full "$PWD/dockutil.pkg" /private/tmp/DockBuilder/temp
        cp -R /private/tmp/DockBuilder/temp/Payload/usr /private/tmp/DockBuilder/files/
        rm -R /private/tmp/DOckBuilder/temp
    fi

    if [[ ! -e /private/tmp/DockBuilder/files/usr/local/bin/dockutil ]]; then
        echo "dockutil binary failed to install in the temp build directory; exiting."
        exit 1
    fi
}

function get_dockutil_pkg () {
    latestDockutilReleaseURL=$(curl -s https://api.github.com/repos/kcrawford/dockutil/releases/latest | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["assets"][0]["browser_download_url"];')
    if [[ ! -e "$PWD/dockutil.pkg" ]]; then
        echo "Getting the latest version of dockutil..."
        curl -L "$latestDockutilReleaseURL" > "$PWD/dockutil.pkg"
        install_dockutil_pkg
    fi
}

# Check for platypus command line, bail if it does not exist
if [[ ! -f /usr/local/bin/platypus ]]; then
    echo "Platypus command line tool not installed, see the following URL for more information:"
    echo "https://github.com/ryangball/DockBuilder/blob/master/README.md#requirements-for-building"
fi

# Update the variables in the dockbuilder.sh script
# If you know of a more elegant/efficient way to do this please create a PR
sed -i .old "s#preferenceFileFullPath=.*#preferenceFileFullPath=\"$preferenceFileFullPath\"#" "$PWD/dockbuilder.sh"

# Create clean temp build directories
find /private/tmp/DockBuilder -mindepth 1 -delete
mkdir -p /private/tmp/DockBuilder/files/Applications/Utilities
mkdir -p /private/tmp/DockBuilder/files/Library/LaunchAgents
mkdir -p /private/tmp/DockBuilder/files/Library/Preferences
mkdir -p /private/tmp/DockBuilder/scripts
mkdir -p "$PWD/build"

# Check for version number as arg 1
if [[ -n "$1" ]]; then
    version="$1"
    echo "Version set to $version"
else
    echo "No version passed, using version $version"
fi

# Make sure dockutil is in the temp build directory
get_dockutil_pkg
install_dockutil_pkg

# Clear the default_items plist if it exists
preferenceFileName="${preferenceFileFullPath##*/}"
if [[ -e "$PWD/$preferenceFileName" ]]; then
    /usr/libexec/PlistBuddy -c Clear "$PWD/$preferenceFileName"
fi
/usr/libexec/PlistBuddy -c "Add :ItemsToAdd array" "$PWD/$preferenceFileName"

# Populate our variables into the plist
defaults write "$PWD/$preferenceFileName" BreadcrumbPath -string "$breadcrumb"
defaults write "$PWD/$preferenceFileName" LogPath -string "$log"
defaults write "$PWD/$preferenceFileName" AppIcon -string "$appIcon"
defaults write "$PWD/$preferenceFileName" HideDockWhileBuilding -bool "$hideDockWhileBuilding"
defaults write "$PWD/$preferenceFileName" HideDockMessage -string "$hideDockMessage"

# Re-populate our ItemsToAdd array
index="0"
for item in "${defaultItemsToAdd[@]}"; do
    plutil -insert ItemsToAdd.$index -string "$item" "$PWD/$preferenceFileName"
    ((index++))
done

# Ensure the plist is xml
plutil -convert xml1 "$PWD/$preferenceFileName"

# Build the .app
echo "Building the .app with Platypus..."
/usr/local/bin/platypus \
    --background \
    --quit-after-execution \
    --app-icon "$appIcon" \
    --name 'DockBuilder' \
    --interface-type 'None' \
    --interpreter '/bin/bash' \
    --author 'Ryan Ball' \
    --app-version "$version" \
    --bundle-identifier "$identifier" \
    --optimize-nib \
    --overwrite \
    'dockbuilder.sh' \
    "/private/tmp/DockBuilder/files/Applications/Utilities/DockBuilder.app"

# Migrate postinstall script to temp build directory
cp "$PWD/postinstall.sh" /private/tmp/DockBuilder/scripts/postinstall
chmod +x /private/tmp/DockBuilder/scripts/postinstall

# Copy the LaunchAgent plist to the temp build directory
cp "$PWD/org.ldschurch.psd.dockbuilder.plist" "/private/tmp/DockBuilder/files/Library/LaunchAgents/"

# Copy the main preference list to the temp build directory
cp "$PWD/$preferenceFileName" "/private/tmp/DockBuilder/files/Library/Preferences/"
chmod 644 "/private/tmp/DockBuilder/files/Library/Preferences/$preferenceFileName"

# Remove any unwanted .DS_Store files from the temp build directory
find "/private/tmp/DockBuilder/" -name '*.DS_Store' -type f -delete

# Remove any extended attributes (ACEs) from the temp build directory
/usr/bin/xattr -rc "/private/tmp/DockBuilder"

echo "Building the PKG..."
/usr/bin/pkgbuild --quiet --root "/private/tmp/DockBuilder/files/" \
    --install-location "/" \
    --scripts "/private/tmp/DockBuilder/scripts/" \
    --identifier "$identifier" \
    --version "$version" \
    --ownership recommended \
    --component-plist "$PWD/DockBuilder-component.plist" \
    "$PWD/build/DockBuilder_VideoProd-${version}.pkg"

exit 0