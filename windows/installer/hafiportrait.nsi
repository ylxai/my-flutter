; ─────────────────────────────────────────────────────────────────────────────
; Hafiportrait Manager — NSIS Installer Script
; ─────────────────────────────────────────────────────────────────────────────
; Requires NSIS 3.x + makensis
; Generated artifact: hafiportrait-manager-setup-{VERSION}-windows-x64.exe

!include "MUI2.nsh"

; ── App Info ─────────────────────────────────────────────────────────────────
!ifndef VERSION
  !define VERSION "0.0.0"
!endif

Name "Hafiportrait Manager ${VERSION}"
OutFile "hafiportrait-manager-setup-${VERSION}-windows-x64.exe"
InstallDir "$PROGRAMFILES64\HafiportraitManager"
InstallDirRegKey HKLM "Software\HafiportraitManager" "Install_Dir"
RequestExecutionLevel admin
BrandingText "Hafiportrait Manager ${VERSION}"

; ── MUI Settings ─────────────────────────────────────────────────────────────
!define MUI_ABORTWARNING
!define MUI_ICON "..\runner\resources\app_icon.ico"
!define MUI_UNICON "..\runner\resources\app_icon.ico"
!define MUI_WELCOMEPAGE_TITLE "Welcome to Hafiportrait Manager ${VERSION}"
!define MUI_WELCOMEPAGE_TEXT "Professional photo file copy utility with high-performance Rust backend.$\r$\n$\r$\nClick Next to continue."
!define MUI_FINISHPAGE_RUN "$INSTDIR\hafiportrait_manager.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch Hafiportrait Manager"

; ── Pages ────────────────────────────────────────────────────────────────────
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; ── Languages ────────────────────────────────────────────────────────────────
!insertmacro MUI_LANGUAGE "English"

; ── Install Sections ─────────────────────────────────────────────────────────
Section "Main Application" SecMain
  SectionIn RO

  SetOutPath "$INSTDIR"

  ; Copy semua file dari build output
  File /r "release\*.*"

  ; Tulis registry untuk uninstaller
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "DisplayName" "Hafiportrait Manager"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "Publisher" "Hafiportrait"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "DisplayIcon" "$INSTDIR\hafiportrait_manager.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager" \
    "NoRepair" 1

  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Start Menu shortcut
  CreateDirectory "$SMPROGRAMS\Hafiportrait Manager"
  CreateShortcut "$SMPROGRAMS\Hafiportrait Manager\Hafiportrait Manager.lnk" \
    "$INSTDIR\hafiportrait_manager.exe"
  CreateShortcut "$SMPROGRAMS\Hafiportrait Manager\Uninstall.lnk" \
    "$INSTDIR\uninstall.exe"

  ; Desktop shortcut
  CreateShortcut "$DESKTOP\Hafiportrait Manager.lnk" \
    "$INSTDIR\hafiportrait_manager.exe"

SectionEnd

; ── Uninstall Section ────────────────────────────────────────────────────────
Section "Uninstall"
  Delete "$INSTDIR\uninstall.exe"
  RMDir /r "$INSTDIR"

  Delete "$SMPROGRAMS\Hafiportrait Manager\Hafiportrait Manager.lnk"
  Delete "$SMPROGRAMS\Hafiportrait Manager\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Hafiportrait Manager"
  Delete "$DESKTOP\Hafiportrait Manager.lnk"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\HafiportraitManager"
  DeleteRegKey HKLM "Software\HafiportraitManager"
SectionEnd
