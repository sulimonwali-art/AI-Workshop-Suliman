@echo off
setlocal
cd /d "%~dp0"
rem Use the Windows inbox PowerShell, current user, and a process-only policy.
rem RemoteSigned keeps downloaded scripts subject to Windows trust checks.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0GamingHelper.ps1"
set "helper_exit=%errorlevel%"
if not "%helper_exit%"=="0" (
  echo.
  echo The helper stopped. Read the error above and the README.
  echo If Windows blocked a downloaded file, inspect it before using Properties ^> Unblock.
  pause
)
endlocal & exit /b %helper_exit%
