Unicode true
RequestExecutionLevel user

!include "MUI2.nsh"

!ifndef PRODUCT_NAME
  !define PRODUCT_NAME "糰糰島"
!endif
!ifndef PRODUCT_ID
  !define PRODUCT_ID "TuanIsland"
!endif
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_ID}"

Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\${PRODUCT_ID}"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "TradChinese"

Section "Game"
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  ClearErrors
  File "${INPUT_DIR}\TuanIsland.exe"
  File "${INPUT_DIR}\island_world_lock.dll"
  File /oname=Godot-LICENSE.txt "${ENGINE_DIR}\LICENSE.txt"
  File /oname=Godot-COPYRIGHT.txt "${ENGINE_DIR}\COPYRIGHT.txt"
  IfErrors failed
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}.lnk" "$INSTDIR\TuanIsland.exe"
  IfErrors failed
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\TuanIsland.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  IfErrors failed
  Goto done
failed:
  Abort "無法安裝糰糰島。請關閉遊戲並確認安裝目錄可寫入。"
done:
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  ClearErrors
  Delete "$INSTDIR\TuanIsland.exe"
  Delete "$INSTDIR\island_world_lock.dll"
  IfErrors failed
  Delete "$INSTDIR\Godot-LICENSE.txt"
  Delete "$INSTDIR\Godot-COPYRIGHT.txt"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}.lnk"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Goto done
failed:
  Abort "請先關閉糰糰島，再解除安裝。"
done:
SectionEnd
