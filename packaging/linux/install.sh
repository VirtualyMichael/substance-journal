#!/usr/bin/env bash
# Run this from inside the extracted SubstanceJournal-*-linux-x86_64 folder
# to add a desktop launcher pointing at this copy of the app.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXE_PATH="$DIR/SubstanceJournal/SubstanceJournal"

if [ ! -x "$EXE_PATH" ]; then
    echo "Could not find $EXE_PATH - run this script from the extracted release folder." >&2
    exit 1
fi

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
DESKTOP_FILE="$APPS_DIR/substance-journal.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Substance Journal
Comment=Local multi-substance ingestion and effect journal
Exec=$EXE_PATH
Terminal=false
Categories=Utility;
EOF
chmod +x "$DESKTOP_FILE"

echo "Installed launcher: $DESKTOP_FILE"
echo "Run directly with: $EXE_PATH"
