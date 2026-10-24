@echo off
chcp 65001 >nul
setlocal
pushd "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" %*
set "RC=%ERRORLEVEL%"

popd
endlocal
if not "%RC%"=="0" (
    echo.
    echo 启动失败，按任意键关闭窗口...
    pause >nul
)
exit /b %RC%
