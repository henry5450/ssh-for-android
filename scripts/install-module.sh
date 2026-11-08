#!/usr/bin/env bash
#
# Optional: expose the client's ssh binary as /system/bin/ssh through a
# KernelSU module overlay. The existing /system/bin/ssh wrapper is backed up
# as ssh-termux-wrapper.
#
# Usage:
#   ./install-module.sh --module /data/adb/modules/custom_system_shell \
#       --binary ./home/usr/bin/ssh --yes
#
# Requires: adb, root (su), a KernelSU module with system/bin/.
# Reboot after running.
#
set -euo pipefail

MODULE="/data/adb/modules/custom_system_shell"
SERIAL=""
BINARY="/data/local/tmp/home/usr/bin/ssh"
YES=0

usage() {
    echo "Usage: $0 [--module <dir>] [--serial <adb-serial>] [--binary <ssh>] [--yes]"
    echo
    echo "Replaces <module>/system/bin/ssh and backs up the old file as"
    echo "ssh-termux-wrapper. Requires root and a reboot."
}

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --module) MODULE="$2"; shift 2 ;;
        --serial) SERIAL="$2"; shift 2 ;;
        --binary) BINARY="$2"; shift 2 ;;
        --yes) YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ "$YES" = 1 ] || {
    echo "This will replace $MODULE/system/bin/ssh." >&2
    echo "Re-run with --yes to proceed." >&2
    exit 1
}
[ -f "$BINARY" ] || die "binary not found: $BINARY"

ADB=(adb)
[ -n "$SERIAL" ] && ADB+=(-s "$SERIAL")

"${ADB[@]}" shell 'su -c id' >/dev/null 2>&1 || \
    die "root (su) is required"

TMP="/data/local/tmp/ssh-module.new"
echo "==> pushing $BINARY"
"${ADB[@]}" push "$BINARY" "$TMP"

echo "==> backing up existing wrapper (if needed)"
"${ADB[@]}" shell "su -c 'test -f $MODULE/system/bin/ssh-termux-wrapper || cp -p $MODULE/system/bin/ssh $MODULE/system/bin/ssh-termux-wrapper'"

echo "==> installing into $MODULE/system/bin/ssh"
"${ADB[@]}" shell "su -c 'cp -f $TMP $MODULE/system/bin/ssh && chmod 0755 $MODULE/system/bin/ssh && chcon u:object_r:system_file:s0 $MODULE/system/bin/ssh $MODULE/system/bin/ssh-termux-wrapper && rm -f $TMP'"

echo
echo "Installed. Reboot required."
echo "Old wrapper: /system/bin/ssh-termux-wrapper"
echo
echo "Note: any script that calls bare 'ssh' (for example ssh-termux) will"
echo "now use this binary. Use /data/data/com.termux/files/usr/bin/ssh"
echo "explicitly if you want the old Termux behavior."
