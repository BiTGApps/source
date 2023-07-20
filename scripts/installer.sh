# This file is part of The BiTGApps Project

# List of GApps Packages
BITGAPPS="
zip/core/ConfigUpdater.tar.xz
zip/core/GmsCoreSetupPrebuilt.tar.xz
zip/core/GoogleExtServices.tar.xz
zip/core/GoogleLoginService.tar.xz
zip/core/GoogleServicesFramework.tar.xz
zip/core/Phonesky.tar.xz
zip/core/PrebuiltGmsCore.tar.xz
zip/sys/GoogleCalendarSyncAdapter.tar.xz
zip/sys/GoogleContactsSyncAdapter.tar.xz
zip/sys/GoogleExtShared.tar.xz
zip/Sysconfig.tar.xz
zip/Default.tar.xz
zip/Permissions.tar.xz
zip/Preferred.tar.xz
zip/overlay/PlayStoreOverlay.tar.xz"

# List of Extra Configs
FRAMEWORK="
zip/framework/DialerPermissions.tar.xz
zip/framework/DialerFramework.tar.xz
zip/framework/MapsPermissions.tar.xz
zip/framework/MapsFramework.tar.xz"

# List of SetupWizard Packages
SETUPWIZARD="
zip/core/GoogleBackupTransport.tar.xz
zip/core/GoogleRestore.tar.xz
zip/core/SetupWizardPrebuilt.tar.xz"

# Local Environment
BB="$TMP/busybox-arm"
rm -rf "$TMP/bin"
install -d "$TMP/bin"
for i in $($BB --list); do
  ln -sf "$BB" "$TMP/bin/$i"
done
PATH="$TMP/bin:$PATH"

# Load utility functions
. $TMP/util_functions.sh

# Helper Functions
ui_print() {
  echo -n -e "ui_print $1\n" >> /proc/self/fd/$OUTFD
  echo -n -e "ui_print\n" >> /proc/self/fd/$OUTFD
}

mk_debug_log() {
  NUM="$(( $RANDOM % 100 )).tar.gz"
  LOG="bitgapps_debug_logs_${NUM}"
  tar -czf "$LOG" "$TMP/recovery.log"
  cp -rf "$LOG" "/sdcard/$LOG"
  cp -rf "$LOG" "$SYSTEM/etc/$LOG"
}

is_mounted() {
  grep -q " $(readlink -f $1) " /proc/mounts 2>/dev/null
  return $?
}

setup_mountpoint() {
  test -L $1 && mv -f $1 ${1}_link
  if [ ! -d $1 ]; then
    rm -f $1
    mkdir $1
  fi
}

mount_apex() {
  test -d "$SYSTEM/apex" || return 255
  ui_print "- Mounting /apex"
  local apex dest loop minorx num var
  setup_mountpoint /apex
  mount -t tmpfs tmpfs /apex -o mode=755 && touch /apex/apex
  test -e /dev/block/loop1 && minorx=$(ls -l /dev/block/loop1 | awk '{ print $6 }') || minorx="1"
  num="0"
  for apex in $SYSTEM/apex/*; do
    dest=/apex/$(basename $apex | sed -E -e 's;\.apex$|\.capex$;;' -e 's;\.current$|\.release$;;');
    mkdir -p $dest
    case $apex in
      *.apex|*.capex)
        unzip -oq $apex original_apex -d /apex
        [ -f "/apex/original_apex" ] && apex="/apex/original_apex"
        unzip -oq $apex apex_payload.img -d /apex
        mv -f /apex/original_apex $dest.apex 2>/dev/null
        mv -f /apex/apex_payload.img $dest.img
        mount -t ext4 -o ro,noatime $dest.img $dest 2>/dev/null
        if [ $? != 0 ]; then
          while [ $num -lt 64 ]; do
            loop=/dev/block/loop$num
            (mknod $loop b 7 $((num * minorx))
            losetup $loop $dest.img) 2>/dev/null
            num=$((num + 1))
            losetup $loop | grep -q $dest.img && break
          done
          mount -t ext4 -o ro,loop,noatime $loop $dest 2>/dev/null
          if [ $? != 0 ]; then
            losetup -d $loop 2>/dev/null
          fi
        fi
      ;;
      *) mount -o bind $apex $dest;;
    esac
  done
  for var in $(grep -o 'export .* /.*' /system_root/init.environ.rc | awk '{ print $2 }'); do
    eval OLD_${var}=\$$var
  done
  $(grep -o 'export .* /.*' /system_root/init.environ.rc | sed 's; /;=/;'); unset export
}

umount_apex() {
  test -d /apex || return 255
  local dest loop var
  for var in $(grep -o 'export .* /.*' /system_root/init.environ.rc | awk '{ print $2 }'); do
    if [ "$(eval echo \$OLD_$var)" ]; then
      eval $var=\$OLD_${var}
    else
      eval unset $var
    fi
    unset OLD_${var}
  done
  for dest in $(find /apex -type d -mindepth 1 -maxdepth 1); do
    loop=$(mount | grep $dest | grep loop | cut -d\  -f1)
    umount -l $dest; [ "$loop" ] && losetup -d $loop
  done
  [ -f /apex/apex ] && umount /apex
  rm -rf /apex 2>/dev/null
}

umount_all() {
  umount -l /system > /dev/null 2>&1
  umount -l /system_root > /dev/null 2>&1
  umount -l /product > /dev/null 2>&1
  umount -l /system_ext > /dev/null 2>&1
  umount -l /vendor > /dev/null 2>&1
  umount -l /persist > /dev/null 2>&1
}

mount_all() {
  [ "$slot" ] || slot=$(getprop ro.boot.slot_suffix)
  [ "$slot" ] || slot=$(grep -o 'androidboot.slot_suffix=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2)
  [ "$slot" ] || slot=$(grep -o 'androidboot.slot=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2)
  mount -o bind /dev/urandom /dev/random
  if ! is_mounted /cache; then
    mount /cache > /dev/null 2>&1
  fi
  if ! is_mounted /data; then
    mount /data > /dev/null 2>&1
  fi
  mount -o ro -t auto /vendor > /dev/null 2>&1
  mount -o ro -t auto /persist > /dev/null 2>&1
  mount -o ro -t auto /product > /dev/null 2>&1
  mount -o ro -t auto /system_ext > /dev/null 2>&1
  [ "$ANDROID_ROOT" ] || ANDROID_ROOT="/system"
  setup_mountpoint $ANDROID_ROOT
  if ! is_mounted $ANDROID_ROOT; then
    mount -o ro -t auto $ANDROID_ROOT > /dev/null 2>&1
  fi
  case $ANDROID_ROOT in
    /system_root) setup_mountpoint /system;;
    /system)
      if ! is_mounted /system && ! is_mounted /system_root; then
        setup_mountpoint /system_root
        mount -o ro -t auto /system_root
      elif [ -f "/system/system/build.prop" ]; then
        setup_mountpoint /system_root
        mount --move /system /system_root
        mount -o bind /system_root/system /system
      fi
      if [ $? != 0 ]; then
        umount -l /system > /dev/null 2>&1
      fi
    ;;
  esac
  case $ANDROID_ROOT in
    /system)
      if ! is_mounted $ANDROID_ROOT && [ -e /dev/block/mapper/system$slot ]; then
        mount -o ro -t auto /dev/block/mapper/system$slot /system_root > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/product$slot /product > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/system_ext$slot /system_ext > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/vendor$slot /vendor > /dev/null 2>&1
      fi
      if ! is_mounted $ANDROID_ROOT && [ -e /dev/block/bootdevice/by-name/system$slot ]; then
        mount -o ro -t auto /dev/block/bootdevice/by-name/system$slot /system_root > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/product$slot /product > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/system_ext$slot /system_ext > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/vendor$slot /vendor > /dev/null 2>&1
      fi
    ;;
  esac
  if is_mounted /system_root; then
    if [ -f "/system_root/build.prop" ]; then
      mount -o bind /system_root /system
    else
      mount -o bind /system_root/system /system
    fi
  fi
  for block in system product system_ext vendor; do
    for slot in "" _a _b; do
      blockdev --setrw /dev/block/mapper/$block$slot > /dev/null 2>&1
    done
  done
  mount -o remount,rw -t auto / > /dev/null 2>&1
  ui_print "- Mounting /system"
  if [ "$(grep -wo '/system' /proc/mounts)" ]; then
    mount -o remount,rw -t auto /system > /dev/null 2>&1
    is_mounted /system || on_abort "! Cannot mount /system"
  fi
  if [ "$(grep -wo '/system_root' /proc/mounts)" ]; then
    mount -o remount,rw -t auto /system_root > /dev/null 2>&1
    is_mounted /system_root || on_abort "! Cannot mount /system_root"
  fi
  ui_print "- Mounting /product"
  mount -o remount,rw -t auto /product > /dev/null 2>&1
  ui_print "- Mounting /system_ext"
  mount -o remount,rw -t auto /system_ext > /dev/null 2>&1
  ui_print "- Mounting /vendor"
  mount -o remount,rw -t auto /vendor > /dev/null 2>&1
  # System is writable
  if ! touch $SYSTEM/.rw 2>/dev/null; then
    on_abort "! Read-only file system"
  fi
  if is_mounted /product; then
    ln -sf /product /system
  fi
  # Dedicated V3 Partitions
  P="/product /system_ext"
}

unmount_all() {
  ui_print "- Unmounting partitions"
  umount -l /system > /dev/null 2>&1
  umount -l /system_root > /dev/null 2>&1
  umount -l /product > /dev/null 2>&1
  umount -l /system_ext > /dev/null 2>&1
  umount -l /vendor > /dev/null 2>&1
  umount -l /persist > /dev/null 2>&1
  umount -l /dev/random > /dev/null 2>&1
}

f_cleanup() { (find .$TMP -mindepth 1 -maxdepth 1 -type f -not -name 'recovery.log' -not -name 'busybox-arm' -exec rm -rf {} \;); }

d_cleanup() { (find .$TMP -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;); }

on_abort() {
  ui_print "$*"
  mk_debug_log
  umount_apex
  unmount_all
  f_cleanup
  d_cleanup
  ui_print "! Installation failed"
  ui_print " "
  true
  sync
  exit 1
}

on_installed() {
  mk_debug_log
  umount_apex
  unmount_all
  f_cleanup
  d_cleanup
  ui_print "- Installation complete"
  ui_print " "
  true
  sync
  exit "$?"
}

get_file_prop() { grep -m1 "^$2=" "$1" | cut -d= -f2; }

get_prop() {
  for f in $PROPFILES; do
    if [ -e "$f" ]; then
      prop="$(get_file_prop "$f" "$1")"
      if [ -n "$prop" ]; then
        break
      fi
    fi
  done
  if [ -z "$prop" ]; then
    getprop "$1" | cut -c1-
  else
    printf "$prop"
  fi
}

extracted() {
  file_list="$(find "$UNZIP_DIR/" -mindepth 1 -type f | cut -d/ -f4-)"
  dir_list="$(find "$UNZIP_DIR/" -mindepth 1 -type d | cut -d/ -f4-)"
  for file in $file_list; do
    install -D "$UNZIP_DIR/${file}" "$SYSTEM/${file}"
    chmod 0644 "$SYSTEM/${file}"
    ch_con system "$SYSTEM/${file}"
    # Overlays require different SELinux context
    case $file in
      */overlay/*) ch_con vendor_overlay "$SYSTEM/${file}";;
    esac
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM/${dir}"
    ch_con system "$SYSTEM/${dir}"
  done
}

# Begin installation
print_title "BiTGApps $version Installer"

# Helper Functions
umount_all
mount_all
mount_apex

# Sideload Optional Configuration
unzip -oq "$ZIPFILE" "bitgapps.conf" -d "$TMP"

# Optional Configuration
for d in /sdcard /sdcard1 /external_sd /data/media/0 /tmp /dev/tmp; do
  for f in $(find $d -type f -iname "bitgapps.conf" 2>/dev/null); do
    if [ -f "$f" ]; then BITGAPPS_CONFIG="$f"; fi
  done
done

# Common Build Properties
PROPFILES="$SYSTEM/build.prop $BITGAPPS_CONFIG"

# Current Package Variables
android_sdk="$(get_prop "ro.build.version.sdk")"
supported_sdk=""
android_version="$(get_prop "ro.build.version.release")"
supported_version=""
device_architecture="$(get_prop "ro.product.cpu.abi")"
supported_architecture=""

# Check Android SDK
if [ "$android_sdk" = "$supported_sdk" ]; then
  ui_print "- Android SDK version: $android_sdk"
else
  on_abort "! Unsupported Android SDK version"
fi

# Check Android Version
if [ "$android_version" = "$supported_version" ]; then
  ui_print "- Android version: $android_version"
else
  on_abort "! Unsupported Android version"
fi

# Check Device Platform
if [ "$device_architecture" = "$supported_architecture" ]; then
  ui_print "- Android platform: $device_architecture"
else
  on_abort "! Unsupported Android platform"
fi

# Check SetupWizard Installation
supported_setup_config="false"
if [ -f "$BITGAPPS_CONFIG" ]; then
  supported_setup_config="$(get_prop "ro.config.setupwizard")"
  # Re-write missing configuration
  if [ -z "$supported_setup_config" ]; then
    supported_setup_config="false"
  fi
fi

# Exclude Reclaimed GApps Space
list_files | while read FILE CLAIMED; do
  PKG="$(find /system -type d -iname $FILE)"
  CLAIMED="$(du -sxk "$PKG" | cut -f1)"
  # Reclaimed GApps Space in KB's
  echo "$CLAIMED" >> $TMP/RAW
done
# Remove White Spaces
sed -i '/^[[:space:]]*$/d' $TMP/RAW
# Reclaimed Removal Space in KB's
if ! grep -soEq '[0-9]+' "$TMP/RAW"; then
  # When raw output of claimed is empty
  CLAIMED="0"
else
  CLAIMED="$(grep -soE '[0-9]+' "$TMP/RAW" | paste -sd+ | bc)"
fi

# Get the available space left on the device
size=`df -k /system | tail -n 1 | tr -s ' ' | cut -d' ' -f4`
# Disk space in human readable format (k=1024)
ds_hr=`df -h /system | tail -n 1 | tr -s ' ' | cut -d' ' -f4`

# Check Required Space
CAPACITY="$(($CAPACITY-$CLAIMED))"
if [ "$size" -gt "$CAPACITY" ]; then
  ui_print "- System Space: $ds_hr"
else
  ui_print "! Insufficient partition size"
  on_abort "! Current space: $ds_hr"
fi

# Delete Runtime Permissions
RTP="$(find /data -type f -iname "runtime-permissions.xml")"
if [ -e "$RTP" ]; then
  if ! grep -qwo 'com.android.vending' $RTP; then
    rm -rf "$RTP"
  fi
fi

# Compressed Packages
ZIP_FILE="$TMP/zip"
# Extracted Packages
mkdir $TMP/unzip
# Initial link
UNZIP_DIR="$TMP/unzip"
# Create links
TMP_SYS="$UNZIP_DIR/app"
TMP_PRIV="$UNZIP_DIR/priv-app"
TMP_FRAMEWORK="$UNZIP_DIR/framework"
TMP_FSVERITY="$UNZIP_DIR/etc/security/fsverity"
TMP_SYSCONFIG="$UNZIP_DIR/etc/sysconfig"
TMP_DEFAULT="$UNZIP_DIR/etc/default-permissions"
TMP_PERMISSION="$UNZIP_DIR/etc/permissions"
TMP_PREFERRED="$UNZIP_DIR/etc/preferred-apps"
TMP_OVERLAY="$UNZIP_DIR/product/overlay"

# Create dir
for d in \
  $UNZIP_DIR/app \
  $UNZIP_DIR/priv-app \
  $UNZIP_DIR/framework \
  $UNZIP_DIR/etc/security/fsverity \
  $UNZIP_DIR/etc/sysconfig \
  $UNZIP_DIR/etc/default-permissions \
  $UNZIP_DIR/etc/permissions \
  $UNZIP_DIR/etc/preferred-apps \
  $UNZIP_DIR/product/overlay; do
  install -d "$d"
  chmod -R 0755 $TMP
done

# Pathmap
SYSTEM_ADDOND="$SYSTEM/addon.d"
SYSTEM_APP="$SYSTEM/app"
SYSTEM_PRIV_APP="$SYSTEM/priv-app"
SYSTEM_ETC_CONFIG="$SYSTEM/etc/sysconfig"
SYSTEM_ETC_DEFAULT="$SYSTEM/etc/default-permissions"
SYSTEM_ETC_PERM="$SYSTEM/etc/permissions"
SYSTEM_ETC_PREF="$SYSTEM/etc/preferred-apps"
SYSTEM_FRAMEWORK="$SYSTEM/framework"
SYSTEM_OVERLAY="$SYSTEM/product/overlay"

# Cleanup
rm -rf $SYSTEM_APP/ExtShared
rm -rf $SYSTEM_APP/FaceLock
rm -rf $SYSTEM_APP/Google*
rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
rm -rf $SYSTEM_PRIV_APP/ExtServices
rm -rf $SYSTEM_PRIV_APP/*Gms*
rm -rf $SYSTEM_PRIV_APP/Google*
rm -rf $SYSTEM_PRIV_APP/Phonesky
rm -rf $SYSTEM_ETC_CONFIG/*google*
rm -rf $SYSTEM_ETC_DEFAULT/default-permissions.xml
rm -rf $SYSTEM_ETC_DEFAULT/bitgapps-permissions.xml
rm -rf $SYSTEM_ETC_DEFAULT/bitgapps-permissions-q.xml
rm -rf $SYSTEM_ETC_PERM/*google*
rm -rf $SYSTEM_ETC_PREF/google.xml
rm -rf $SYSTEM_OVERLAY/PlayStoreOverlay.apk
rm -rf $SYSTEM_ADDOND/70-bitgapps.sh

# Google Apps Packages
ui_print "- Installing GApps"
for f in $BITGAPPS; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
tar -xf $ZIP_FILE/sys/GoogleCalendarSyncAdapter.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/sys/GoogleContactsSyncAdapter.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/sys/GoogleExtShared.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/core/ConfigUpdater.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/GmsCoreSetupPrebuilt.tar.xz -C $TMP_PRIV 2>/dev/null
tar -xf $ZIP_FILE/core/GoogleExtServices.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/GoogleLoginService.tar.xz -C $TMP_PRIV 2>/dev/null
tar -xf $ZIP_FILE/core/GoogleServicesFramework.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/Phonesky.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/PrebuiltGmsCore.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/Sysconfig.tar.xz -C $TMP_SYSCONFIG
tar -xf $ZIP_FILE/Default.tar.xz -C $TMP_DEFAULT
tar -xf $ZIP_FILE/Permissions.tar.xz -C $TMP_PERMISSION
tar -xf $ZIP_FILE/Preferred.tar.xz -C $TMP_PREFERRED
tar -xf $ZIP_FILE/overlay/PlayStoreOverlay.tar.xz -C $TMP_OVERLAY 2>/dev/null
# Remove Compressed Packages
for f in $BITGAPPS; do rm -rf $TMP/$f; done

# REQUEST NETWORK SCORES
if [ "$android_sdk" -le "28" ]; then
  rm -rf $TMP_DEFAULT/bitgapps-permissions-q.xml
fi
if [ "$android_sdk" -ge "29" ]; then
  rm -rf $TMP_DEFAULT/bitgapps-permissions.xml
fi

# Additional Components
for f in $FRAMEWORK; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
tar -xf $ZIP_FILE/framework/DialerPermissions.tar.xz -C $TMP_PERMISSION
tar -xf $ZIP_FILE/framework/DialerFramework.tar.xz -C $TMP_FRAMEWORK
tar -xf $ZIP_FILE/framework/MapsPermissions.tar.xz -C $TMP_PERMISSION
tar -xf $ZIP_FILE/framework/MapsFramework.tar.xz -C $TMP_FRAMEWORK

# Install OTA Survival Script
if [ -d "$SYSTEM_ADDOND" ]; then
  ui_print "- Installing OTA survival script"
  ADDOND="70-bitgapps.sh"
  unzip -oq "$ZIPFILE" "$ADDOND" -d "$TMP"
  # Install OTA survival script
  rm -rf $SYSTEM_ADDOND/$ADDOND
  cp -f $TMP/$ADDOND $SYSTEM_ADDOND/$ADDOND
  chmod 0755 $SYSTEM_ADDOND/$ADDOND
  ch_con system "$SYSTEM_ADDOND/$ADDOND"
fi

# Allow SetupWizard to survive OTA upgrade
if [ "$supported_setup_config" = "true" ]; then
  sed -i -e 's/"false"/"true"/g' $SYSTEM_ADDOND/$ADDOND
fi

# Install SetupWizard Components
if [ "$supported_setup_config" = "true" ]; then
  ui_print "- Installing SetupWizard"
  for f in $SYSTEM $SYSTEM/product $SYSTEM/system_ext $P; do
    find $f -type d -iname '*Provision*' -exec rm -rf {} \;
    find $f -type d -iname '*GoogleBackup*' -exec rm -rf {} \;
    find $f -type d -iname '*GoogleRestore*' -exec rm -rf {} \;
    find $f -type d -iname '*SetupWizard*' -exec rm -rf {} \;
  done
  for f in $SETUPWIZARD; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
  if [ -f "$ZIP_FILE/core/GoogleBackupTransport.tar.xz" ]; then
    tar -xf $ZIP_FILE/core/GoogleBackupTransport.tar.xz -C $TMP_PRIV
  fi
  if [ -f "$ZIP_FILE/core/GoogleRestore.tar.xz" ]; then
    tar -xf $ZIP_FILE/core/GoogleRestore.tar.xz -C $TMP_PRIV
  fi
  tar -xf $ZIP_FILE/core/SetupWizardPrebuilt.tar.xz -C $TMP_PRIV
  # Remove Compressed Packages
  for f in $SETUPWIZARD; do rm -rf $TMP/$f; done
fi

# Integrity Signing Certificate
unzip -oq "$ZIPFILE" "zip/Certificate.tar.xz" -d "$TMP"
tar -xf $ZIP_FILE/Certificate.tar.xz -C "$TMP_FSVERITY"

# Helper Functions
extracted

# Enable Doze Mode for GMS
DOZE='/allow-in-power-save package="com.google.android.gms"/d'
sed -i -e "$DOZE" /system/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/product/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/system_ext/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /product/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /system_ext/etc/sysconfig/*.xml 2>/dev/null
# FIXIT: SYSCONFIG IN PRIVILEGED PERMISSIONS
sed -i -e "$DOZE" /system/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/product/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/system_ext/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /product/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /system_ext/etc/permissions/*.xml 2>/dev/null

# End installation
on_installed
