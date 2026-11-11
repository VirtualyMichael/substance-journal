<#
.SYNOPSIS
  Builds the Wear OS watch app and installs it on a watch over Wi-Fi (ADB debugging).
.EXAMPLE
  scripts\install_watch.ps1 -Address 192.168.1.50:5555
  scripts\install_watch.ps1 -Address 192.168.1.50:5555 -PairAddress 192.168.1.50:41234 -PairCode 123456
#>
param(
  [Parameter(Mandatory = $true)][string]$Address,
  [string]$PairAddress,
  [string]$PairCode
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "adb not found at $adb" }

Push-Location (Join-Path $repo 'app\android')
try {
  & .\gradlew.bat :wear:assembleRelease
  if ($LASTEXITCODE -ne 0) { throw 'The watch app did not build.' }
} finally { Pop-Location }

$apk = Join-Path $repo 'app\build\wear\outputs\apk\release\wear-release.apk'
if (-not (Test-Path $apk)) { throw "Built app not found at $apk" }

if ($PairAddress -and $PairCode) {
  & $adb pair $PairAddress $PairCode
  if ($LASTEXITCODE -ne 0) { throw 'Pairing with the watch failed.' }
}
& $adb connect $Address
& $adb -s $Address install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'Installing on the watch failed. Check ADB debugging and Debug over Wi-Fi are on.' }
& $adb -s $Address shell am start -n com.substancejournal.substance_journal_app/com.substancejournal.watch.MainActivity | Out-Null
Write-Host 'Installed on the watch.'
