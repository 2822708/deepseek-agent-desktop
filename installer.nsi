; DeepSeek Agent Desktop - NSIS Installer Script
; Usage: makensis /DARCH=x64 installer.nsi   (or x86)

!ifndef ARCH
  !define ARCH "x64"
!endif

!if "${ARCH}" == "x64"
  !define ARCH_LABEL "x64"
!else
  !define ARCH_LABEL "x86"
!endif

Name "DeepSeek Agent Desktop"
OutFile "dist\DeepSeekAgentDesktop-Setup-${ARCH_LABEL}.exe"
Unicode True
ShowInstDetails show
ShowUnInstDetails show
SetCompressor /SOLID lzma
RequestExecutionLevel admin

VIAddVersionKey "ProductName" "DeepSeek Agent Desktop"
VIAddVersionKey "CompanyName" "DeepSeek"
VIAddVersionKey "FileDescription" "DeepSeek Agent Desktop Installer"
VIAddVersionKey "FileVersion" "1.1.0.0"
VIAddVersionKey "ProductVersion" "1.1.0.0"
VIProductVersion "1.1.0.0"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "Sections.nsh"

!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\DeepSeekAgentDesktop.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch DeepSeek Agent Desktop"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\README.md"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "View README"
!define MUI_FINISHPAGE_TITLE "Installation Complete"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; --- Custom install path ---
!define APP_DIR_NAME "DeepSeekAgentDesktop"

; Initial directory: $PROGRAMFILES\DeepSeekAgentDesktop
InstallDir "$PROGRAMFILES\${APP_DIR_NAME}"
; Allow user to browse for a parent folder; we always append ${APP_DIR_NAME}

!define MUI_DIRECTORYPAGE_VERIFYONLEAVE

Var WebView2Needed
Var DotNetNeeded

Function CheckWebView2
  StrCpy $WebView2Needed "0"
  ClearErrors
  ReadRegStr $0 HKLM "SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
  IfErrors 0 +3
    ReadRegStr $0 HKLM "SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
    IfErrors 0 +2
      StrCpy $WebView2Needed "1"
  ${If} $0 == ""
    StrCpy $WebView2Needed "1"
  ${EndIf}
FunctionEnd

Function CheckDotNet
  ; pythonnet uses the built-in .NET Framework on Windows.
  ; Check for .NET Framework 4.x via registry (present on Windows 10/11 by default).
  StrCpy $DotNetNeeded "0"
  ClearErrors
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Version"
  IfErrors 0 +3
    ReadRegStr $0 HKLM "SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP\v4\Full" "Version"
    IfErrors 0 +1
      StrCpy $DotNetNeeded "1"
  ${If} $0 == ""
    StrCpy $DotNetNeeded "1"
  ${EndIf}
FunctionEnd

; --- Append subfolder to user-selected path ---
Function .onVerifyInstDir
  ; If user-selected path does NOT end with \${APP_DIR_NAME}, append it
  ${If} ${ARCH} == "x64"
    ${If} $INSTDIR == "$PROGRAMFILES"
      StrCpy $INSTDIR "$PROGRAMFILES\${APP_DIR_NAME}"
    ${EndIf}
  ${Else}
    ${If} $INSTDIR == "$PROGRAMFILES32"
      StrCpy $INSTDIR "$PROGRAMFILES32\${APP_DIR_NAME}"
    ${EndIf}
  ${EndIf}
FunctionEnd

; --- Install Section ---
Section "Install (required)" SecInstall
  SectionIn RO
  SetOutPath "$INSTDIR"

  File "dist\DeepSeekAgentDesktop-${ARCH_LABEL}.exe"
  Delete "$INSTDIR\DeepSeekAgentDesktop.exe"
  Rename "$INSTDIR\DeepSeekAgentDesktop-${ARCH_LABEL}.exe" "$INSTDIR\DeepSeekAgentDesktop.exe"
  File "README.md"
  File "app.ico"

  ; --- WebView2 Runtime ---
  DetailPrint "Checking WebView2 Runtime..."
  Call CheckWebView2
  ${If} $WebView2Needed == "1"
    DetailPrint "WebView2 Runtime not found. Downloading..."
    NSISdl::download "https://go.microsoft.com/fwlink/p/?LinkId=2124703" "$TEMP\MicrosoftEdgeWebview2Setup.exe"
    Pop $R0
    ${If} $R0 == "success"
      DetailPrint "Installing WebView2 Runtime..."
      nsExec::ExecToLog '"$TEMP\MicrosoftEdgeWebview2Setup.exe" /silent /install'
      Pop $0
      ${If} $0 != 0
        MessageBox MB_ICONEXCLAMATION "WebView2 Runtime installation may have failed (code $0).$\r$\nPlease install manually from:$\r$\nhttps://developer.microsoft.com/microsoft-edge/webview2/"
      ${EndIf}
      Delete "$TEMP\MicrosoftEdgeWebview2Setup.exe"
    ${Else}
      MessageBox MB_ICONEXCLAMATION "Failed to download WebView2 Runtime.$\r$\nPlease install manually from:$\r$\nhttps://developer.microsoft.com/microsoft-edge/webview2/"
    ${EndIf}
  ${Else}
    DetailPrint "WebView2 Runtime already installed."
  ${EndIf}

  ; --- .NET Framework 4.x (only for rare stripped-down systems) ---
  DetailPrint "Checking .NET Framework..."
  Call CheckDotNet
  ${If} $DotNetNeeded == "1"
    DetailPrint ".NET Framework 4.x not found. Downloading..."
    NSISdl::download "https://go.microsoft.com/fwlink/?linkid=2088631" "$TEMP\ndp48-web.exe"
    Pop $R0
    ${If} $R0 == "success"
      DetailPrint "Installing .NET Framework 4.8..."
      nsExec::ExecToLog '"$TEMP\ndp48-web.exe" /q /norestart'
      Pop $0
      ${If} $0 != 0
        MessageBox MB_ICONEXCLAMATION ".NET Framework installation may have failed (code $0).$\r$\nPlease install manually from:$\r$\nhttps://dotnet.microsoft.com/download/dotnet-framework/net48"
      ${EndIf}
      Delete "$TEMP\ndp48-web.exe"
    ${Else}
      MessageBox MB_ICONEXCLAMATION "Failed to download .NET Framework (code $R0).$\r$\nPlease install manually from:$\r$\nhttps://dotnet.microsoft.com/download/dotnet-framework/net48"
    ${EndIf}
  ${Else}
    DetailPrint ".NET Framework already installed."
  ${EndIf}

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "DisplayName" "DeepSeek Agent Desktop"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "DisplayIcon" "$INSTDIR\app.ico"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "DisplayVersion" "1.1.0"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "Publisher" "DeepSeek"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "InstallLocation" "$INSTDIR"
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "NoModify" 1
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "NoRepair" 1
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop" "EstimatedSize" 21000

  ; Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\DeepSeek Agent"
  CreateShortcut "$SMPROGRAMS\DeepSeek Agent\DeepSeek Agent.lnk" "$INSTDIR\DeepSeekAgentDesktop.exe" "" "$INSTDIR\app.ico"
  CreateShortcut "$SMPROGRAMS\DeepSeek Agent\Uninstall.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\app.ico"
SectionEnd

; --- Optional: Desktop shortcut (default ON) ---
Section "Desktop shortcut" SecDesktop
  SectionIn 1  ; default checked (1 = selected)
  CreateShortcut "$DESKTOP\DeepSeek Agent.lnk" "$INSTDIR\DeepSeekAgentDesktop.exe" "" "$INSTDIR\app.ico"
SectionEnd

; --- Optional: Auto-start with Windows (default OFF) ---
Section "Auto-start with Windows" SecAutoStart
  CreateShortcut "$SMSTARTUP\DeepSeek Agent.lnk" "$INSTDIR\DeepSeekAgentDesktop.exe" "" "$INSTDIR\app.ico"
SectionEnd

; --- Descriptions ---
LangString DESC_SecInstall ${LANG_SIMPCHINESE} "DeepSeek Agent Desktop (with WebView2 and .NET Framework auto-install)"
LangString DESC_SecInstall ${LANG_ENGLISH} "DeepSeek Agent Desktop core application (includes WebView2 and .NET Framework auto-install)"
LangString DESC_SecDesktop ${LANG_SIMPCHINESE} "Create desktop shortcut"
LangString DESC_SecDesktop ${LANG_ENGLISH} "Create a DeepSeek Agent shortcut on the Desktop"
LangString DESC_SecAutoStart ${LANG_SIMPCHINESE} "Auto-start with Windows"
LangString DESC_SecAutoStart ${LANG_ENGLISH} "Start DeepSeek Agent automatically when Windows starts"

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
!insertmacro MUI_DESCRIPTION_TEXT ${SecInstall} $(DESC_SecInstall)
!insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_SecDesktop)
!insertmacro MUI_DESCRIPTION_TEXT ${SecAutoStart} $(DESC_SecAutoStart)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; --- Uninstall Section ---
Section "Uninstall"
  nsExec::ExecToLog 'taskkill /F /IM DeepSeekAgentDesktop.exe /T'
  Delete "$INSTDIR\DeepSeekAgentDesktop.exe"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\app.ico"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$SMPROGRAMS\DeepSeek Agent\DeepSeek Agent.lnk"
  Delete "$SMPROGRAMS\DeepSeek Agent\Uninstall.lnk"
  Delete "$DESKTOP\DeepSeek Agent.lnk"
  Delete "$SMSTARTUP\DeepSeek Agent.lnk"
  RMDir "$SMPROGRAMS\DeepSeek Agent"
  DeleteRegKey SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekAgentDesktop"
  RMDir "$INSTDIR"
  SetAutoClose True
SectionEnd