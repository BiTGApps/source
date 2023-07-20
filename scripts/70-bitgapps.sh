#!/sbin/sh
#
# This file is part of The BiTGApps Project

# ADDOND_VERSION=3

if [ -z "$backuptool_ab" ]; then
  SYS="$S"
  TMP=/tmp
else
  SYS="/postinstall/system"
  TMP="/postinstall/tmp"
fi

# Required for SetupWizard
setup_config="false"

# Dedicated V3 Partitions
P="/product /system_ext /postinstall/product /postinstall/system_ext"

. /tmp/backuptool.functions

list_files() {
cat <<EOF
app/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
app/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
app/GoogleExtShared/GoogleExtShared.apk
priv-app/ConfigUpdater/ConfigUpdater.apk
priv-app/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
priv-app/GoogleBackupTransport/GoogleBackupTransport.apk
priv-app/GoogleExtServices/GoogleExtServices.apk
priv-app/GoogleLoginService/GoogleLoginService.apk
priv-app/GoogleRestore/GoogleRestore.apk
priv-app/GoogleServicesFramework/GoogleServicesFramework.apk
priv-app/Phonesky/Phonesky.apk
priv-app/PrebuiltGmsCore/PrebuiltGmsCore.apk
priv-app/SetupWizardPrebuilt/SetupWizardPrebuilt.apk
etc/default-permissions/default-permissions.xml
etc/default-permissions/bitgapps-permissions.xml
etc/default-permissions/bitgapps-permissions-q.xml
etc/permissions/android.ext.services.xml
etc/permissions/com.google.android.dialer.support.xml
etc/permissions/com.google.android.maps.xml
etc/permissions/privapp-permissions-google.xml
etc/permissions/split-permissions-google.xml
etc/preferred-apps/google.xml
etc/sysconfig/google.xml
etc/sysconfig/google_build.xml
etc/sysconfig/google_exclusives_enable.xml
etc/sysconfig/google-hiddenapi-package-whitelist.xml
etc/sysconfig/google-install-constraints-allowlist.xml
etc/sysconfig/google-rollback-package-whitelist.xml
etc/sysconfig/google-staged-installer-whitelist.xml
etc/security/fsverity/gms_fsverity_cert.der
etc/security/fsverity/play_store_fsi_cert.der
framework/com.google.android.dialer.support.jar
framework/com.google.android.maps.jar
product/overlay/PlayStoreOverlay.apk
EOF
}

case "$1" in
  backup)
    list_files | while read FILE DUMMY; do
      backup_file $S/"$FILE"
    done
  ;;
  restore)
    if [ "$setup_config" = "true" ]; then
      for f in $SYS $SYS/product $SYS/system_ext $P; do
        find $f -type d -iname '*Provision*' -exec rm -rf {} \;
        find $f -type d -iname '*SetupWizard*' -exec rm -rf {} \;
      done
    fi
    list_files | while read FILE REPLACEMENT; do
      R=""
      [ -n "$REPLACEMENT" ] && R="$S/$REPLACEMENT"
      [ -f "$C/$S/$FILE" ] && restore_file $S/"$FILE" "$R"
    done
    rm -rf $SYS/app/ExtShared $SYS/priv-app/ExtServices
    for i in $(list_files); do
      chown root:root "$SYS/$i" 2>/dev/null
      chmod 644 "$SYS/$i" 2>/dev/null
      chmod 755 "$(dirname "$SYS/$i")" 2>/dev/null
    done
  ;;
esac
