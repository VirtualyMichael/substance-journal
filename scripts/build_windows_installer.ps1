<#
.SYNOPSIS
  Builds the Windows app and wraps it in an installer (dist\installer\SubstanceJournal-<version>-setup.exe).
  Needs Flutter and Inno Setup 6 (https://jrsoftware.org/isdl.php). Without Inno Setup it still
  builds the app and prints where the files are.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $repo 'app')
try {
  $version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
} finally { Pop-Location }

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
  Write-Warning 'Inno Setup 6 not found: skipping the installer. The app is in app\build\windows\x64\runner\Release.'
  exit 0
}
& $iscc "/DAppVersion=$version" (Join-Path $repo 'packaging\windows\installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Write-Host "Installer: $(Join-Path $repo "dist\installer\SubstanceJournal-$version-setup.exe")"
