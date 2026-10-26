<#
.SYNOPSIS
  Creates the release signing key for the Android app and tells Gradle to use it.

.DESCRIPTION
  Until this has been run, release APKs are signed with Android's shared debug key, which is
  fine for testing. Signing with your own key means updates install over each other and nobody
  else can publish an update that replaces your app.

  IMPORTANT: a phone that has the debug-signed build cannot update to a build signed with this
  key. Android refuses, and the app has to be uninstalled first, which DELETES its data.
  Do this once: make an encrypted backup (Settings > Backup and export) or sync to your PC,
  uninstall the old app, then install the new one and restore.

  The keystore and its password are written outside the repository, in
  $env:USERPROFILE\.substance-journal\. Back that folder up somewhere safe. If it is lost you can
  never publish an update that installs over the current one.
#>
param(
  [string]$Folder = (Join-Path $env:USERPROFILE '.substance-journal')
)

$ErrorActionPreference = 'Stop'
$keytool = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe'
if (-not (Test-Path $keytool)) { $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source }
if (-not $keytool) { throw 'keytool not found. Install Android Studio or a JDK.' }

New-Item -ItemType Directory -Force $Folder | Out-Null
$store = Join-Path $Folder 'upload-keystore.jks'
if (Test-Path $store) { throw "A keystore already exists at $store. Delete it only if you are sure; it cannot be recreated." }

$bytes = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$password = [Convert]::ToBase64String($bytes).Replace('/', '_').Replace('+', '-')

& $keytool -genkeypair -v -keystore $store -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
  -alias substance-journal -storepass $password -keypass $password `
  -dname 'CN=Substance Journal, O=Personal, C=US'
if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }

$repoRoot = Split-Path -Parent $PSScriptRoot
$props = Join-Path $repoRoot 'app\android\key.properties'
@"
storePassword=$password
keyPassword=$password
keyAlias=substance-journal
storeFile=$($store.Replace('\', '/'))
"@ | Set-Content -Encoding ascii $props

Write-Host "Keystore: $store"
Write-Host "Gradle settings: $props (ignored by git)"
Write-Host 'Back up the whole folder. Then build with: flutter build apk --release'
