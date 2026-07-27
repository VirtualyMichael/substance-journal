#!/usr/bin/env bash
set -euo pipefail

SKIP_TESTS=0
NO_SHORTCUT=0
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
        --no-shortcut) NO_SHORTCUT=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

VENV_PYTHON="$PROJECT_ROOT/.venv/bin/python"
VENV_PYINSTALLER="$PROJECT_ROOT/.venv/bin/pyinstaller"
EXE_PATH="$PROJECT_ROOT/dist/SubstanceJournal/SubstanceJournal"

echo "Substance Journal build"
echo "Project: $PROJECT_ROOT"

if [ ! -x "$VENV_PYTHON" ]; then
    echo "Creating local virtual environment..."
    python3 -m venv .venv
fi

echo "Installing/updating dependencies..."
"$VENV_PYTHON" -m pip install -r requirements.txt

echo "Checking Python syntax..."
"$VENV_PYTHON" -m py_compile \
    substance_journal/__main__.py \
    substance_journal/app.py \
    substance_journal/core/paths.py \
    substance_journal/core/models.py \
    substance_journal/core/reference_data.py \
    substance_journal/core/database.py \
    substance_journal/core/interactions.py \
    substance_journal/core/tolerance.py \
    substance_journal/core/alcohol_import.py \
    substance_journal/ui/theme.py \
    substance_journal/ui/widgets.py \
    substance_journal/ui/dialogs.py \
    substance_journal/ui/main_window.py \
    tests/test_core.py

if [ "$SKIP_TESTS" -eq 0 ]; then
    echo "Running tests..."
    "$VENV_PYTHON" -m unittest tests.test_core
fi

echo "Building windowed executable..."
"$VENV_PYINSTALLER" --noconfirm --windowed --name SubstanceJournal --paths . substance_journal/__main__.py

if [ ! -f "$EXE_PATH" ]; then
    echo "Build finished but executable was not found at $EXE_PATH" >&2
    exit 1
fi
chmod +x "$EXE_PATH"

if [ "$NO_SHORTCUT" -eq 0 ]; then
    echo "Creating/updating application launcher..."
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
    echo "Launcher: $DESKTOP_FILE"
fi

echo "Build complete: $EXE_PATH"
