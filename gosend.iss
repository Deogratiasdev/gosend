[Setup]
AppId={{A9241B32-E82B-4A11-8578-83C1A2E30E9B}
AppName=GoSend
AppVersion=1.0.0
AppPublisher=Déo-Gratias
DefaultDirName={autopf}\GoSend
DefaultGroupName=GoSend
OutputDir=Output
OutputBaseFilename=GoSend_Setup
Compression=lzma
SolidCompression=yes
; Assure-toi que cette icône existe si tu veux une icône personnalisée
; SetupIconFile=C:\Users\User\OneDrive\Desktop\GoSend\assets\app_icon.png

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; IMPORTANT: Assure-toi que ce chemin correspond bien au dossier de ton projet
Source: "C:\Users\User\OneDrive\Desktop\GoSend\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\GoSend"; Filename: "{app}\gosend.exe"
Name: "{autodesktop}\GoSend"; Filename: "{app}\gosend.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gosend.exe"; Description: "{cm:LaunchProgram,GoSend}"; Flags: nowait postinstall skipifsilent