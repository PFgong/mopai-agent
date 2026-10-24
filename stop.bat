@echo off
chcp 65001 >nul
setlocal
pushd "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop.ps1" %*

popd
endlocal
echo.
echo 按任意键关闭窗口...
pause >nul
