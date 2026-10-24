<#
    mopai-agent 停止服务（Windows）

    用法：双击仓库根目录的 stop.bat，或
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stop.ps1
#>
param()

$ErrorActionPreference = 'Continue'
$ports = @(8000, 8001, 8080)

Write-Host ""
Write-Host "  正在停止墨排本地服务…" -ForegroundColor Cyan
Write-Host ""

$stopped = 0
foreach ($port in $ports) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) {
        Write-Host "  [OK]   端口 $port 无服务" -ForegroundColor DarkGray
        continue
    }
    foreach ($c in $conns) {
        $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if ($p -and $p.Id -ne $PID) {
            Write-Host "  [OK]   端口 $port -> 结束 $($p.ProcessName) (PID $($p.Id))" -ForegroundColor Green
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $stopped++
        }
    }
}

Write-Host ""
if ($stopped -gt 0) {
    Write-Host "  已停止 $stopped 个进程。" -ForegroundColor Green
} else {
    Write-Host "  没有正在运行的墨排服务。" -ForegroundColor Yellow
}
Write-Host ""
exit 0
