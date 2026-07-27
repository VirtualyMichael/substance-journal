param(
    [switch]$SkipTests,
    [switch]$NoShortcut
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

$VenvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$VenvPyInstaller = Join-Path $ProjectRoot ".venv\Scripts\pyinstaller.exe"
$ExePath = Join-Path $ProjectRoot "dist\SubstanceJournal\SubstanceJournal.exe"

Write-Host "Substance Journal build" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

if (-not (Test-Path $VenvPython)) {
    Write-Host "Creating local virtual environment..."
    python -m venv .venv
}

Write-Host "Installing/updating dependencies..."
& $VenvPython -m pip install -r requirements.txt

Write-Host "Checking Python syntax..."
& $VenvPython -m py_compile `
    substance_journal\__main__.py `
    substance_journal\app.py `
    substance_journal\core\paths.py `
    substance_journal\core\models.py `
    substance_journal\core\reference_data.py `
    substance_journal\core\database.py `
    substance_journal\core\interactions.py `
    substance_journal\ui\theme.py `
    substance_journal\ui\dialogs.py `
    substance_journal\ui\main_window.py `
    tests\test_core.py

if (-not $SkipTests) {
    Write-Host "Running tests..."
    & $VenvPython -m unittest tests.test_core
}

Write-Host "Building windowed executable..."
& $VenvPyInstaller --noconfirm --windowed --name SubstanceJournal --paths . substance_journal\__main__.py

if (-not (Test-Path $ExePath)) {
    throw "Build finished but executable was not found at $ExePath"
}

if (-not $NoShortcut) {
    Write-Host "Creating/updating desktop shortcut..."
    $Desktop = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $Desktop "Substance Journal.lnk"
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = Split-Path $ExePath
    $Shortcut.Description = "Substance Journal"
    $Shortcut.Save()
    Write-Host "Shortcut: $ShortcutPath"
}

Write-Host "Build complete: $ExePath" -ForegroundColor Green
