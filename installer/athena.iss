; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

#define MyAppName "Athena"
#define MyAppVersion "6.3.0a6"
#define MyAppPublisher "Jet Propulsion Laboratory, California Institute of Technology"
#define MyAppExeName "athenawb.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{C6674C4E-EA24-4564-A280-DF3FEF793FAA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
;AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={pf}\Athena {#MyAppVersion}
DefaultGroupName=Athena {#MyAppVersion}
LicenseFile=..\LICENSE
;InfoBeforeFile=before.txt
InfoAfterFile=after.txt
;OutputDir=
OutputBaseFilename=Athena{#MyAppVersion}_Installer
SetupIconFile=athena.ico
Compression=lzma
SolidCompression=yes
ChangesAssociations=yes
WizardImageFile=WizardLogo.bmp
WizardImageStretch=no
WizardSmallImageFile=SmallWizardLogo.bmp


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]             
Source: "..\bin\athenawb-{#MyAppVersion}-win32-ix86.exe"; DestDir: "{app}"; DestName: "athenawb.exe"; Flags: ignoreversion
Source: "..\docs\build_notes.html"; DestDir: "{app}\docs"; Flags: ignoreversion 
Source: "..\docs\index.html"; DestDir: "{app}\docs"; Flags: ignoreversion 
Source: "..\docs\*.png"; DestDir: "{app}\docs"; Flags: ignoreversion 
Source: "..\docs\athena.helpdb"; DestDir: "{app}\docs"; Flags: ignoreversion 
Source: "..\docs\man1\athena.html"; DestDir: "{app}\docs\man1"; Flags: ignoreversion 
Source: "..\docs\man1\athena_batch.html"; DestDir: "{app}\docs\man1"; Flags: ignoreversion 
Source: "..\docs\*.docx"; DestDir: "{app}\docs\dev"; Flags: ignoreversion 
Source: "..\docs\*.pptx"; DestDir: "{app}\docs\dev"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\docs\*.pdf"; DestDir: "{app}\docs\dev"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\maps\*.png"; DestDir: "{app}\maps"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\maps\*.tif"; DestDir: "{app}\maps"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\data\polygons\*.npf"; DestDir: "{app}\data\polygons"; Flags: ignoreversion
Source: "..\data\polygons\*.kml"; DestDir: "{app}\data\polygons"; Flags: ignoreversion
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Dirs]
Name: "{app}\mods"
Name: "{userdocs}\Athena"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{userdocs}\Athena"
Name: "{group}\Athena Documentation"; Filename: "{app}\docs\index.html"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{userdocs}\Athena"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: ".adb"; ValueType: string; ValueName: ""; ValueData: "AthenaScenarioFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "AthenaScenarioFile"; ValueType: string; ValueName: ""; ValueData: "Athena Scenario File"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "AthenaScenarioFile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\ATHENA.EXE,0"
Root: HKCR; Subkey: "AthenaScenarioFile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\ATHENA.EXE"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, "&", "&&")}}"; WorkingDir: "{userdocs}\Athena"; Flags: nowait postinstall skipifsilent

