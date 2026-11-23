; Instalador de Windows de "Cuerpo Humano 3D" (NSIS 3, interfaz moderna, en español).
; Se genera desde macOS o Windows con:
;     makensis instalador/instalador.nsi
; Necesita antes el .exe exportado por Godot en builds/windows/CuerpoHumano3D.exe.
; Resultado: builds/windows/Instalar_CuerpoHumano3D.exe

Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!define NOMBRE "Cuerpo Humano 3D"
!define EJECUTABLE "CuerpoHumano3D.exe"
!define VERSION "0.1.0"
!define EDITOR "Grupo BIOLOGIA3D"
!define CLAVE_DESINSTALAR "Software\Microsoft\Windows\CurrentVersion\Uninstall\CuerpoHumano3D"

Name "${NOMBRE}"
OutFile "..\builds\windows\Instalar_CuerpoHumano3D.exe"
InstallDir "$PROGRAMFILES64\${NOMBRE}"
InstallDirRegKey HKLM "${CLAVE_DESINSTALAR}" "InstallLocation"
RequestExecutionLevel admin
BrandingText "${NOMBRE} ${VERSION}"

VIProductVersion "0.1.0.0"
VIAddVersionKey "ProductName" "${NOMBRE}"
VIAddVersionKey "FileDescription" "Instalador de ${NOMBRE}"
VIAddVersionKey "CompanyName" "${EDITOR}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Modelos: Z-Anatomy (CC BY-SA 4.0), HRA (CC BY 4.0)"

!include "MUI2.nsh"

!define MUI_ICON "..\ui\icono.ico"
!define MUI_UNICON "..\ui\icono.ico"
!define MUI_ABORTWARNING

; Páginas del instalador: bienvenida, créditos, componentes, carpeta, instalación y final
!define MUI_WELCOMEPAGE_TITLE "Bienvenido al instalador de ${NOMBRE}"
!define MUI_WELCOMEPAGE_TEXT "Este asistente instalará ${NOMBRE} ${VERSION}, un atlas 3D interactivo del cuerpo humano con simulaciones fisiológicas.$\r$\n$\r$\nPulsa Siguiente para continuar."
!insertmacro MUI_PAGE_WELCOME
!define MUI_LICENSEPAGE_TEXT_TOP "Créditos y licencias de los modelos anatómicos."
!define MUI_LICENSEPAGE_BUTTON "Siguiente >"
!define MUI_LICENSEPAGE_TEXT_BOTTOM "Pulsa Siguiente para continuar."
!insertmacro MUI_PAGE_LICENSE "creditos.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EJECUTABLE}"
!define MUI_FINISHPAGE_RUN_TEXT "Abrir ${NOMBRE} ahora"
!insertmacro MUI_PAGE_FINISH

; Páginas del desinstalador
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Spanish"

Section "${NOMBRE} (necesario)" SecPrincipal
	SectionIn RO
	SetOutPath "$INSTDIR"
	File "..\builds\windows\${EJECUTABLE}"
	File "creditos.txt"
	WriteUninstaller "$INSTDIR\Desinstalar.exe"
	; Menú Inicio
	CreateDirectory "$SMPROGRAMS\${NOMBRE}"
	CreateShortcut "$SMPROGRAMS\${NOMBRE}\${NOMBRE}.lnk" "$INSTDIR\${EJECUTABLE}"
	CreateShortcut "$SMPROGRAMS\${NOMBRE}\Desinstalar ${NOMBRE}.lnk" "$INSTDIR\Desinstalar.exe"
	; Agregar o quitar programas
	WriteRegStr HKLM "${CLAVE_DESINSTALAR}" "DisplayName" "${NOMBRE}"
	WriteRegStr HKLM "${CLAVE_DESINSTALAR}" "DisplayVersion" "${VERSION}"
	WriteRegStr HKLM "${CLAVE_DESINSTALAR}" "Publisher" "${EDITOR}"
	WriteRegStr HKLM "${CLAVE_DESINSTALAR}" "DisplayIcon" "$INSTDIR\${EJECUTABLE}"
	WriteRegStr HKLM "${CLAVE_DESINSTALAR}" "InstallLocation" "$INSTDIR"
	WriteRegStr HKLM "${CLAVE_DESINSTALAR}" "UninstallString" '"$INSTDIR\Desinstalar.exe"'
	WriteRegDWORD HKLM "${CLAVE_DESINSTALAR}" "NoModify" 1
	WriteRegDWORD HKLM "${CLAVE_DESINSTALAR}" "NoRepair" 1
	WriteRegDWORD HKLM "${CLAVE_DESINSTALAR}" "EstimatedSize" 245000
SectionEnd

Section "Acceso directo en el escritorio" SecEscritorio
	SetShellVarContext all
	CreateShortcut "$DESKTOP\${NOMBRE}.lnk" "$INSTDIR\${EJECUTABLE}"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
	!insertmacro MUI_DESCRIPTION_TEXT ${SecPrincipal} "La aplicación (unos 240 MB)."
	!insertmacro MUI_DESCRIPTION_TEXT ${SecEscritorio} "Crea un ícono en el escritorio para abrir la aplicación."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
	SetShellVarContext all
FunctionEnd

Function un.onInit
	SetShellVarContext all
FunctionEnd

Section "Uninstall"
	Delete "$INSTDIR\${EJECUTABLE}"
	Delete "$INSTDIR\creditos.txt"
	Delete "$INSTDIR\Desinstalar.exe"
	RMDir "$INSTDIR"
	Delete "$SMPROGRAMS\${NOMBRE}\${NOMBRE}.lnk"
	Delete "$SMPROGRAMS\${NOMBRE}\Desinstalar ${NOMBRE}.lnk"
	RMDir "$SMPROGRAMS\${NOMBRE}"
	Delete "$DESKTOP\${NOMBRE}.lnk"
	DeleteRegKey HKLM "${CLAVE_DESINSTALAR}"
	; Los puntajes y preferencias del usuario (AppData) se conservan
SectionEnd
