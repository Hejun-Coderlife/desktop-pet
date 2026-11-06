; Pip 桌面宠物 · Windows 安装包（Inno Setup 6，免费）
; 编译：先 dotnet build windows/Pip.csproj -c Release，再
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" windows\installer\Pip.iss
; 输出 dist\Pip-Setup-<版本>.exe（dist/ 不进仓库）
;
; - 装到当前用户自己的目录（%LOCALAPPDATA%\Programs\Pip），不要管理员权限，普通账号也能装
; - 开始菜单 + 桌面图标；可选开机自启，跟 Pip 托盘菜单里的「开机自动启动」是同一个注册表值（HKCU\...\Run\Pip）
; - 装 / 升级 / 卸载前先 Pip.exe --quit 让正在跑的 Pip 自己退出，exe 不会被占用
; - 卸载删掉程序、开机自启和设置（HKCU\Software\Pip），在「设置 → 应用」里能看到、能卸载
; 没有代码签名（要花钱），对方第一次运行安装包会弹「Windows 已保护你的电脑」：更多信息 → 仍要运行

#define AppName "Pip 桌面宠物"
#define AppVersion "1.0.0"
#define BinDir "..\bin\Release\net48"

[Setup]
AppId={{6C2B7E61-3F7A-4C1E-9B8D-5A0F2E9C4D17}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Pip
DefaultDirName={autopf}\Pip
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\..\dist
OutputBaseFilename=Pip-Setup-{#AppVersion}
SetupIconFile=..\app.ico
UninstallDisplayIcon={app}\Pip.exe
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no

[Languages]
; 简体中文翻译取自 Inno Setup 官方仓库（Files/Languages/ChineseSimplified.isl），winget 装的版本里没带，放在本目录
Name: "chs"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "在桌面上放一个图标"
Name: "autostart"; Description: "开机自动启动 Pip"

[Files]
Source: "{#BinDir}\Pip.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\Pip.exe.config"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\Pip.exe"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\Pip.exe"; Tasks: desktopicon

[Registry]
; 开机自启：值的写法跟 WinPlatform.AutoStart 一样（带引号的 exe 路径），托盘菜单里能照常开关
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Pip"; ValueData: """{app}\Pip.exe"""; Tasks: autostart; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Pip"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Pip"; Flags: uninsdeletekey dontcreatekey

[Run]
Filename: "{app}\Pip.exe"; Description: "现在打开 Pip"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\Pip.exe"; Parameters: "--quit"; Flags: runhidden waituntilterminated; RunOnceId: "QuitPip"

[Code]
// 升级时先让旧的 Pip 退出，不然 Pip.exe 被占用替换不了
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Exe: String;
  Code: Integer;
begin
  Result := '';
  Exe := ExpandConstant('{app}\Pip.exe');
  if FileExists(Exe) then
  begin
    Exec(Exe, '--quit', '', SW_HIDE, ewWaitUntilTerminated, Code);
    Sleep(1500);
  end;
end;

// 卸载：--quit 之后等一下再删文件
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then Sleep(1500);
end;
