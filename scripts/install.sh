#!/usr/bin/env bash
#
# Install the prebuilt OpenSSH client into /data/local/tmp/home on a device.
#
# Usage:
#   ./install.sh [--home <dir>] [--serial <adb-serial>] [--dry-run]
#
# In the release zip, --home defaults to ./home.
# In this repository, use e.g. --home build/stage/home.
#
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_SRC="$SELF_DIR/home"
SERIAL=""
DRY_RUN=0
DEST="/data/local/tmp/home"

usage() {
    echo "Usage: $0 [--home <dir>] [--serial <adb-serial>] [--dry-run]"
    echo
    echo "Installs the client tree into $DEST."
    echo "No keys are generated and an existing .ssh/config is preserved."
}

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --home) HOME_SRC="$2"; shift 2 ;;
        --serial) SERIAL="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -d "$HOME_SRC/usr/bin" ] || die "home tree not found: $HOME_SRC/usr/bin"

ADB=(adb)
[ -n "$SERIAL" ] && ADB+=(-s "$SERIAL")

run_adb() {
    echo "+ adb $*"
    [ "$DRY_RUN" = 1 ] || "${ADB[@]}" "$@"
}

run_shell() {
    echo "+ adb shell $*"
    [ "$DRY_RUN" = 1 ] || "${ADB[@]}" shell "$*"
}

if [ "$DRY_RUN" = 0 ]; then
    command -v adb >/dev/null 2>&1 || die "missing tool: adb"
    ABI="$("${ADB[@]}" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')"
    [ "$ABI" = "arm64-v8a" ] || die "expected arm64-v8a device, got '${ABI:-unknown}'"
fi

echo "==> creating $DEST"
run_shell "mkdir -p $DEST/usr/bin $DEST/usr/libexec $DEST/usr/etc/ssh $DEST/.ssh $DEST/tmp"

echo "==> pushing files"
run_adb push "$HOME_SRC/usr/bin/." "$DEST/usr/bin/"
run_adb push "$HOME_SRC/usr/libexec/." "$DEST/usr/libexec/"
run_adb push "$HOME_SRC/usr/etc/ssh/ssh_config" "$DEST/usr/etc/ssh/ssh_config"

# Install the config template only when none exists.
run_adb push "$HOME_SRC/.ssh/config" "$DEST/.ssh/config.new"
run_shell "if [ -f $DEST/.ssh/config ]; then echo 'keeping existing .ssh/config'; else mv $DEST/.ssh/config.new $DEST/.ssh/config; fi; rm -f $DEST/.ssh/config.new"

echo "==> setting permissions"
run_shell "chmod 0755 $DEST/usr/bin/ssh $DEST/usr/bin/scp $DEST/usr/bin/sftp $DEST/usr/bin/ssh-add $DEST/usr/bin/ssh-agent $DEST/usr/bin/ssh-keygen $DEST/usr/bin/ssh-keyscan $DEST/usr/libexec/ssh-pkcs11-helper $DEST/usr/libexec/ssh-sk-helper"
run_shell "chmod 0644 $DEST/usr/etc/ssh/ssh_config"
run_shell "chmod 0700 $DEST/.ssh"
run_shell "chmod 0600 $DEST/.ssh/config"

echo
echo "Installed. No keys were generated."
echo "Try:"
echo "  adb shell '$DEST/usr/bin/ssh -V'"
echo "  adb shell '$DEST/usr/bin/ssh -G example.com | grep userknownhostsfile'"
