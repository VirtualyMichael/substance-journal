#!/usr/bin/env bash
# Builds the Linux app on this Windows PC inside WSL (Ubuntu), so it does not depend on GitHub Actions.
#
#   wsl -d Ubuntu-24.04 -u root -- bash "$(wslpath -a scripts/build_linux_wsl.sh)" "$(wslpath -a .)"
#
# First run installs the build tools and Flutter (a few GB); later runs only rebuild.
# Output: dist/release-<version>/SubstanceJournal-<version>-linux-x64.tar.gz
set -euo pipefail

REPO="${1:?pass the repository path as seen from WSL}"
USER_NAME=builder

if [ "$(id -u)" = 0 ]; then
  if ! command -v cmake >/dev/null || ! dpkg -s libgtk-3-dev >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      clang cmake ninja-build pkg-config libgtk-3-dev libsqlite3-dev libsecret-1-dev \
      curl git unzip xz-utils zip rsync libglu1-mesa ca-certificates
  fi
  id "$USER_NAME" >/dev/null 2>&1 || useradd -m -s /bin/bash "$USER_NAME"
  exec su - "$USER_NAME" -c "bash '$0' '$REPO'"
fi

FLUTTER="$HOME/flutter"
if [ ! -x "$FLUTTER/bin/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER"
fi
export PATH="$FLUTTER/bin:$PATH"
export CI=true
flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true

# Build on WSL's own disk: far faster than /mnt/c, and the Windows build folders stay untouched.
WORK="$HOME/sj-build"
mkdir -p "$WORK"
rsync -a --delete --exclude build --exclude .dart_tool --exclude windows/flutter/ephemeral \
  "$REPO/app/" "$WORK/app/"
cd "$WORK/app"

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//; s/+.*//')"
flutter pub get
flutter build linux --release

OUT="$REPO/dist/release-$VERSION"
mkdir -p "$OUT"
tar -C build/linux/x64/release/bundle -czf "$OUT/SubstanceJournal-$VERSION-linux-x64.tar.gz" .
echo "Built: $OUT/SubstanceJournal-$VERSION-linux-x64.tar.gz"
