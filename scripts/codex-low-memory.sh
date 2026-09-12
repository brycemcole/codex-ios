#!/bin/sh
set -u

backup=/var/mobile/codex-port-install/low-memory-backup
mkdir -p "$backup"

plists="
/System/Library/LaunchDaemons/com.apple.searchd.plist
/System/Library/LaunchDaemons/com.apple.mobileassetd.plist
/System/Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist
/System/Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist
/System/Library/LaunchDaemons/com.apple.tipsd.plist
/System/Library/LaunchDaemons/com.apple.assistantd.plist
/System/Library/LaunchDaemons/com.apple.assistant_service.plist
/System/Library/LaunchDaemons/com.apple.voiced.plist
/System/Library/LaunchDaemons/com.apple.routined.plist
/System/Library/LaunchDaemons/com.apple.adid.plist
/System/Library/LaunchDaemons/com.apple.storebookkeeperd.plist
/System/Library/LaunchDaemons/com.apple.gamed.plist
"

for plist in $plists; do
    cp -p "$plist" "$backup/${plist##*/}"
done

case "${1:-status}" in
    disable)
        for plist in $plists; do
            launchctl unload -w "$plist" >/dev/null 2>&1 || true
        done
        echo "low-memory profile disabled services"
        ;;
    enable)
        for plist in $plists; do
            launchctl load -w "$plist" >/dev/null 2>&1 || true
        done
        echo "low-memory profile restored services"
        ;;
    status)
        launchctl list | grep -E 'com.apple.(searchd|mobileassetd|mobile.softwareupdated|softwareupdateservicesd|tipsd|assistantd|assistant_service|voiced|routined|adid|storebookkeeperd|gamed)$' || true
        ;;
    *)
        echo "usage: $0 disable|enable|status" >&2
        exit 2
        ;;
esac
