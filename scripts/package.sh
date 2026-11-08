#!/usr/bin/env bash
#
# Package a staged home tree as ssh-for-android-v10.6p1-aarch64.zip.
#
# Usage: ./scripts/package.sh [stage-home-dir] [output-dir]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${1:-$ROOT/build/stage/home}"
OUT="${2:-$ROOT/build/dist}"
NAME="ssh-for-android-v10.6p1-aarch64"

die() { echo "error: $*" >&2; exit 1; }

command -v zip >/dev/null 2>&1 || die "missing tool: zip"
command -v sha256sum >/dev/null 2>&1 || die "missing tool: sha256sum"
[ -d "$STAGE/usr/bin" ] || die "stage tree not found: $STAGE"
STAGE="$(cd "$STAGE" && pwd)"

mkdir -p "$OUT"
rm -rf "$OUT/$NAME" "$OUT/$NAME.zip" "$OUT/SHA256SUMS"
mkdir -p "$OUT/$NAME/home"

cp -a "$STAGE/." "$OUT/$NAME/home/"
install -m 0755 "$ROOT/scripts/install.sh" "$OUT/$NAME/install.sh"
install -m 0644 "$ROOT/LICENSE" "$ROOT/LICENSE.openssh" "$ROOT/LICENSE.openssl" \
    "$OUT/$NAME/"

cat > "$OUT/$NAME/README.txt" <<'EOF'
OpenSSH 10.6p1 client for Android arm64 (aarch64).

The binaries are built for these exact paths:
  HOME:   /data/local/tmp/home
  prefix: /data/local/tmp/home/usr

Install with adb:
  ./install.sh --serial <adb-serial>

Or manually:
  adb push home/. /data/local/tmp/home/
  adb shell 'chmod 0755 /data/local/tmp/home/usr/bin/* \
                    /data/local/tmp/home/usr/libexec/*; \
             chmod 0700 /data/local/tmp/home/.ssh; \
             chmod 0600 /data/local/tmp/home/.ssh/config'

No keys are included. Generate your own with:
  ssh-keygen -t ed25519 -N ''

See https://github.com/henry5450/ssh-for-android for details.
EOF

(
    cd "$OUT"
    zip -r -q "$NAME.zip" "$NAME"
    sha256sum "$NAME.zip" > SHA256SUMS
)

echo "Created:"
echo "  $OUT/$NAME.zip"
echo "  $OUT/SHA256SUMS"
