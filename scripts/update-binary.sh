#!/sbin/sh
#
# This file is part of The BiTGApps Project

# Default Permission
umask 022

# Manipulate SELinux State
setenforce 0

# Set environmental variables in the global environment
export ZIPFILE="$3"
export OUTFD="$2"
export TMP="/tmp"
export ASH_STANDALONE=1
export SYSTEM="/system"

# Extract bundled busybox
unzip -o "$ZIPFILE" "busybox-arm" -d "$TMP"
chmod +x "$TMP/busybox-arm"

# Extract utility script
unzip -o "$ZIPFILE" "util_functions.sh" -d "$TMP"
chmod +x "$TMP/util_functions.sh"

# Extract installer script
unzip -o "$ZIPFILE" "installer.sh" -d "$TMP"
chmod +x "$TMP/installer.sh"

# Execute installer script
exec $TMP/busybox-arm sh "$TMP/installer.sh" "$@"

# Exit
exit "$?"
