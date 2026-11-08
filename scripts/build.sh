#!/usr/bin/env bash
#
# Build the OpenSSH 10.6p1 client for Android arm64 (bionic).
#
# Requirements: Linux x86_64, Android NDK r29, gcc, make, perl, m4, curl,
# patch, zip. No sudo/root is required.
#
# Usage:
#   ANDROID_NDK_ROOT=/path/to/android-ndk-r29 ./scripts/build.sh [workdir]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-$ROOT/build}"
NDK="${ANDROID_NDK_ROOT:-/Application/android-ndk-r29}"
API="${ANDROID_API:-28}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

OPENSSH_COMMIT="26b1363c7"
OPENSSL_VERSION="3.5.5"
AUTOCONF_VERSION="2.72"
PREFIX="/data/local/tmp/home/usr"

TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
CC="$TC/bin/aarch64-linux-android${API}-clang"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

for t in curl tar make perl m4 gcc patch zip sha256sum install; do
    need "$t"
done
[ -x "$CC" ] || die "Android NDK clang not found: $CC (set ANDROID_NDK_ROOT)"

mkdir -p "$WORK/src" "$WORK/tools" "$WORK/logs" "$WORK/stage" "$WORK/dist"

fetch() {
    local dest="$1"; shift
    local url
    if [ -s "$dest" ]; then
        return 0
    fi
    echo "==> downloading $(basename "$dest")"
    for url in "$@"; do
        if curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
                --max-time 1800 -o "${dest}.part" "$url"; then
            mv "${dest}.part" "$dest"
            return 0
        fi
        rm -f "${dest}.part"
        echo "    download failed, trying next mirror" >&2
    done
    die "failed to download $(basename "$dest")"
}

show_tail() {
    [ -f "$1" ] && tail -40 "$1" >&2 || true
}

fetch "$WORK/src/autoconf-${AUTOCONF_VERSION}.tar.xz" \
    "https://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz" \
    "https://mirrors.kernel.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz"
fetch "$WORK/src/openssl-${OPENSSL_VERSION}.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
fetch "$WORK/src/openssh-${OPENSSH_COMMIT}.tar.gz" \
    "https://github.com/openssh/openssh-portable/archive/${OPENSSH_COMMIT}.tar.gz" \
    "https://codeload.github.com/openssh/openssh-portable/tar.gz/${OPENSSH_COMMIT}"

# ---------------------------------------------------------------- autoconf
if [ ! -x "$WORK/tools/bin/autoconf" ]; then
    echo "==> building autoconf ${AUTOCONF_VERSION}"
    rm -rf "$WORK/src/autoconf-${AUTOCONF_VERSION}"
    tar -C "$WORK/src" -xf "$WORK/src/autoconf-${AUTOCONF_VERSION}.tar.xz"
    (
        cd "$WORK/src/autoconf-${AUTOCONF_VERSION}"
        if ! ./configure --prefix="$WORK/tools" \
                > "$WORK/logs/autoconf-configure.log" 2>&1; then
            show_tail "$WORK/logs/autoconf-configure.log"; exit 1
        fi
        if ! make -j"$JOBS" MAKEINFO=true \
                > "$WORK/logs/autoconf-make.log" 2>&1; then
            show_tail "$WORK/logs/autoconf-make.log"; exit 1
        fi
        if ! make install MAKEINFO=true \
                > "$WORK/logs/autoconf-install.log" 2>&1; then
            show_tail "$WORK/logs/autoconf-install.log"; exit 1
        fi
    )
fi

# ----------------------------------------------------------------- OpenSSL
if [ ! -f "$WORK/tools/openssl-android/lib/libcrypto.a" ]; then
    echo "==> building OpenSSL ${OPENSSL_VERSION} (static, arm64)"
    rm -rf "$WORK/src/openssl-${OPENSSL_VERSION}"
    tar -C "$WORK/src" -xf "$WORK/src/openssl-${OPENSSL_VERSION}.tar.gz"
    (
        cd "$WORK/src/openssl-${OPENSSL_VERSION}"
        export ANDROID_NDK_ROOT="$NDK"
        export PATH="$TC/bin:$PATH"
        if ! ./Configure android-arm64 \
                --prefix="$WORK/tools/openssl-android" \
                --openssldir="$WORK/tools/openssl-android/ssl" \
                --libdir=lib \
                no-shared no-tests no-docs no-apps no-module -fPIC \
                -D__ANDROID_API__="$API" \
                > "$WORK/logs/openssl-configure.log" 2>&1; then
            show_tail "$WORK/logs/openssl-configure.log"; exit 1
        fi
        if ! make -j"$JOBS" > "$WORK/logs/openssl-make.log" 2>&1; then
            show_tail "$WORK/logs/openssl-make.log"; exit 1
        fi
        if ! make install_sw > "$WORK/logs/openssl-install.log" 2>&1; then
            show_tail "$WORK/logs/openssl-install.log"; exit 1
        fi
    )
fi

# ----------------------------------------------------------------- OpenSSH
SRC="$WORK/src/openssh-${OPENSSH_COMMIT}"
if [ ! -d "$SRC" ]; then
    echo "==> extracting OpenSSH ${OPENSSH_COMMIT}"
    archive="$WORK/src/openssh-${OPENSSH_COMMIT}.tar.gz"
    top="$(tar -tzf "$archive" | sed -n '1p' | cut -d/ -f1)"
    rm -rf "$WORK/src/$top" "$SRC"
    tar -C "$WORK/src" -xf "$archive"
    if [ "$WORK/src/$top" != "$SRC" ]; then
        mv "$WORK/src/$top" "$SRC"
    fi
fi

apply_patch() {
    local patch_file="$1" marker="$2" marker_file="$3"
    if grep -q "$marker" "$SRC/$marker_file" 2>/dev/null; then
        echo "    skipping $(basename "$patch_file") (already applied)"
        return 0
    fi
    echo "    applying $(basename "$patch_file")"
    ( cd "$SRC" && patch -p1 --batch --forward < "$patch_file" >/dev/null )
}

echo "==> applying Android patches"
apply_patch "$ROOT/patches/0001-android-home.patch" \
    "SSH_ANDROID_HOME" "misc.c"
apply_patch "$ROOT/patches/0002-android-explicit-bzero.patch" \
    "ssh_memset" "openbsd-compat/explicit_bzero.c"
apply_patch "$ROOT/patches/0003-readconf-perm.patch" \
    "Bad permissions on %s" "readconf.c"
apply_patch "$ROOT/patches/0004-android-getrrsetbyname-stub.patch" \
    "SSHFP-over-DNS" "openbsd-compat/getrrsetbyname.c"
apply_patch "$ROOT/patches/0005-android-freerrset-stub.patch" \
    "Nothing was allocated by the Android stub" "openbsd-compat/getrrsetbyname.c"
apply_patch "$ROOT/patches/0006-android-no-hardlink.patch" \
    "Android denies hard links" "hostfile.c"

echo "==> generating configure"
(
    cd "$SRC"
    cp m4/openssh.m4 aclocal.m4
    PATH="$WORK/tools/bin:$PATH" autoconf
    PATH="$WORK/tools/bin:$PATH" autoheader
)

echo "==> configuring OpenSSH"
export PATH="$WORK/tools/bin:$TC/bin:$PATH"
export CC="$CC"
export LD="$CC"
export AR="$TC/bin/llvm-ar"
export RANLIB="$TC/bin/llvm-ranlib"
export STRIP="$TC/bin/llvm-strip"
export NM="$TC/bin/llvm-nm"

cd "$SRC"
CPPFLAGS="-DHAVE_ATTRIBUTE__SENTINEL__=1" \
ac_cv_func_endgrent=yes \
ac_cv_func_fmt_scaled=no \
ac_cv_func_getlastlogxbyname=no \
ac_cv_func_readpassphrase=no \
ac_cv_func_strnvis=no \
ac_cv_header_sys_un_h=yes \
ac_cv_lib_crypt_crypt=no \
ac_cv_search_getrrsetbyname=no \
ac_cv_func_bzero=yes \
./configure \
    --host=aarch64-linux-android \
    --build=x86_64-pc-linux-gnu \
    --prefix="$PREFIX" \
    --sysconfdir="$PREFIX/etc/ssh" \
    --with-pid-dir="$PREFIX/var/run" \
    --with-privsep-path="$PREFIX/var/empty" \
    --with-pie=yes \
    --without-rpath \
    --with-ssl-dir="$WORK/tools/openssl-android" \
    --with-maildir="$PREFIX/var/mail" \
    --with-default-path="$PREFIX/bin:/system/bin:/system/xbin" \
    --with-superuser-path="$PREFIX/bin:/system/bin:/system/xbin" \
    --disable-strip \
    --disable-libutil \
    --disable-utmp --disable-wtmp --disable-lastlog \
    --disable-utmpx --disable-wtmpx \
    --disable-pututline --disable-pututxline \
    --disable-etc-default-login \
    --without-pam --without-selinux --without-audit \
    --without-ldns --without-libedit --without-kerberos5 \
    PATH_PASSWD_PROG=/system/bin/passwd \
    > "$WORK/logs/openssh-configure.log" 2>&1 || {
        show_tail "$WORK/logs/openssh-configure.log"; exit 1;
    }

echo "==> building client binaries"
if ! make -j"$JOBS" \
        ssh scp sftp ssh-add ssh-agent ssh-keygen ssh-keyscan \
        ssh-pkcs11-helper ssh-sk-helper ssh_config.out \
        > "$WORK/logs/openssh-make.log" 2>&1; then
    show_tail "$WORK/logs/openssh-make.log"; exit 1
fi

# ------------------------------------------------------------------ stage
echo "==> staging"
STAGE="$WORK/stage/home"
rm -rf "$WORK/stage"
mkdir -p "$STAGE/usr/bin" "$STAGE/usr/libexec" "$STAGE/usr/etc/ssh" \
    "$STAGE/.ssh" "$STAGE/tmp"

for b in ssh scp sftp ssh-add ssh-agent ssh-keygen ssh-keyscan; do
    install -m 0755 "$b" "$STAGE/usr/bin/"
done
for b in ssh-pkcs11-helper ssh-sk-helper; do
    install -m 0755 "$b" "$STAGE/usr/libexec/"
done
install -m 0644 ssh_config.out "$STAGE/usr/etc/ssh/ssh_config"

"$TC/bin/llvm-strip" --strip-unneeded "$STAGE"/usr/bin/* "$STAGE"/usr/libexec/*

cat > "$STAGE/.ssh/config" <<'EOF'
# OpenSSH client config for this Android build.
# This build forces its home directory to /data/local/tmp/home
# (override with the SSH_ANDROID_HOME environment variable).
# Add your Host blocks below; id_* keys are not created automatically.
EOF

chmod 0700 "$STAGE/.ssh" "$STAGE/tmp"
chmod 0600 "$STAGE/.ssh/config"

# ---------------------------------------------------------------- package
"$ROOT/scripts/package.sh" "$STAGE" "$WORK/dist"

echo
echo "Build complete:"
echo "  stage: $STAGE"
echo "  zip:   $WORK/dist/ssh-for-android-v10.6p1-aarch64.zip"
echo "  sums:  $WORK/dist/SHA256SUMS"
