@echo off
rem Build Lothal.exe natively on Windows. Same steps as build_windows.sh, minus wine:
rem Godot runs rcedit directly here.
rem
rem The .exe is UNSIGNED. SmartScreen will show "Windows protected your PC" until the release
rem has reputation or an EV cert. Users get past it with More info -> Run anyway.
setlocal enabledelayedexpansion
cd /d "%~dp0"

if "%GODOT%"=="" set "GODOT=godot"
set "VERSION=4.7.1.stable"
set "TEMPLATE_DIR=%APPDATA%\Godot\export_templates\%VERSION%"
set "OUT=build\windows\Lothal.exe"

where "%GODOT%" >nul 2>&1 || (
  echo error: '%GODOT%' not on PATH. Install Godot %VERSION% or set GODOT to its full path. 1>&2
  exit /b 1
)

for /f "delims=" %%v in ('"%GODOT%" --version 2^>nul') do (
  if "!HAVE!"=="" set "HAVE=%%v"
)
echo !HAVE! | findstr /b /c:"%VERSION%" >nul || (
  echo error: expected Godot %VERSION%, found !HAVE! 1>&2
  exit /b 1
)

if not exist "%TEMPLATE_DIR%\windows_release_x86_64.exe" (
  echo error: Windows export template missing at: 1>&2
  echo        %TEMPLATE_DIR%\windows_release_x86_64.exe 1>&2
  exit /b 1
)

rem encrypt_pck=true against stock templates exports fine and then cannot decrypt its own pack
rem at startup. The key must be compiled INTO the template.
findstr /b /c:"encrypt_pck=true" export_presets.cfg >nul && (
  if not exist "%TEMPLATE_DIR%\.lothal_encrypted" (
    echo error: encrypt_pck=true but the installed export templates carry no encryption key. 1>&2
    echo        This export would produce a build that cannot start. 1>&2
    echo        Build encrypted templates first, or set encrypt_pck=false. 1>&2
    exit /b 1
  )
  for /f "usebackq delims= " %%k in ("%TEMPLATE_DIR%\.lothal_encrypted") do set "SCRIPT_AES256_ENCRYPTION_KEY=%%k"
  echo ==^> exporting with PCK encryption
)

if "%RCEDIT%"=="" set "RCEDIT=%USERPROFILE%\.lothal\rcedit-x64.exe"
if not exist "%RCEDIT%" (
  echo warning: rcedit not found at %RCEDIT% 1>&2
  echo          The .exe will carry Godot's default icon and no version metadata. 1>&2
  echo          Fix: download rcedit-x64.exe from 1>&2
  echo          https://github.com/electron/rcedit/releases into %USERPROFILE%\.lothal\ 1>&2
  echo          and set it in Godot: Editor Settings -^> Export -^> Windows -^> rcedit. 1>&2
)

if not "%SKIP_TESTS%"=="1" (
  echo ==^> running test suite
  "%GODOT%" --headless --script res://tests/run_tests.gd || exit /b 1
)

echo ==^> exporting %OUT%
if exist build\windows rmdir /s /q build\windows
mkdir build\windows
"%GODOT%" --headless --export-release "Windows Desktop" "%OUT%" || exit /b 1

if not exist "%OUT%" (
  echo error: export produced no executable at %OUT% 1>&2
  exit /b 1
)

rem The .pck sits beside the .exe unless embedded. Both must travel together in the zip.
echo.
echo built: %CD%\build\windows
dir /b build\windows
