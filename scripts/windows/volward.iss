#ifndef AppVersion
#define AppVersion "0.0.2"
#endif

#ifndef SourceDir
#define SourceDir "..\..\apps\volward\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
#define OutputDir "..\..\build\release"
#endif

#ifndef IconFile
#define IconFile "..\..\apps\volward\windows\runner\resources\app_icon.ico"
#endif

[Setup]
AppId=Volward
AppName=Volward
AppVersion={#AppVersion}
AppPublisher=Volward
DefaultDirName={localappdata}\Programs\Volward
DefaultGroupName=Volward
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=VolwardSetup-v{#AppVersion}-windows-x64
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\volward.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Volward"; Filename: "{app}\volward.exe"
Name: "{group}\Uninstall Volward"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Volward"; Filename: "{app}\volward.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\volward.exe"; Description: "{cm:LaunchProgram,Volward}"; Flags: nowait postinstall skipifsilent
