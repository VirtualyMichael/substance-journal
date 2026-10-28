; Inno Setup script for the Substance Journal Windows installer.
; Build with scripts\build_windows_installer.ps1 (which passes /DAppVersion=...).
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif

[Setup]
AppId={{6B2F0F4A-7C1E-4D55-9E3B-5B7C1C1B0A11}
AppName=Substance Journal
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
AppVersion={#AppVersion}
AppPublisher=Substance Journal
DefaultDirName={autopf}\Substance Journal
DefaultGroupName=Substance Journal
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist\installer
OutputBaseFilename=SubstanceJournal-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\substance_journal_app.exe

[Files]
Source: "..\..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Substance Journal"; Filename: "{app}\substance_journal_app.exe"
Name: "{autodesktop}\Substance Journal"; Filename: "{app}\substance_journal_app.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\substance_journal_app.exe"; Description: "Start Substance Journal"; Flags: nowait postinstall skipifsilent

; Your journal lives in your user data folder, not here, so uninstalling or updating the program never touches it.
