<#
    mopai-agent 一键启动（Windows）

    用法：
        A. 双击仓库根目录的 start.bat
        B. PowerShell 中执行：
           powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start.ps1

    可选参数：
        -NoBrowser   启动成功但不自动打开浏览器
        -Reset       启动前先停掉占用 8000 / 8001 / 8080 的进程
        -Detached    启动成功后立即返回，不进入「按 Q 停止」的等待循环

    流程：检查工具链 → 准备 Python 环境 → 检查端口 → 启动三个服务 → 健康检查
          成功：生成并在浏览器打开结果页（含工作台链接、Token、工具状态）
          失败：逐条打印原因与修复办法
#>
param(
    [switch]$NoBrowser,
    [switch]$Reset,
    [switch]$Detached
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$root      = Split-Path -Parent $PSScriptRoot
$agentDir  = Join-Path $root 'agent'
$distDir   = Join-Path $root 'dist'
$logDir    = Join-Path $agentDir 'logs'
$venvPy    = Join-Path $agentDir '.venv\Scripts\python.exe'
$reqFile   = Join-Path $agentDir 'requirements.txt'

$AGENT_TOKEN    = if ($env:MOPAI_AGENT_TOKEN)    { $env:MOPAI_AGENT_TOKEN }    else { 'local-dev-token' }
$COMPILER_TOKEN = if ($env:MOPAI_COMPILER_TOKEN) { $env:MOPAI_COMPILER_TOKEN } else { 'local-compiler-token' }
$AGENT_PORT     = 8000
$COMPILER_PORT  = 8001
$WEB_PORT       = 8080
$AGENT_URL      = "http://127.0.0.1:$AGENT_PORT"
$COMPILER_URL   = "http://127.0.0.1:$COMPILER_PORT"
$WEB_URL        = "http://localhost:$WEB_PORT"

# ------------------------------------------------------------------ 输出辅助
function Write-Head { param($Text) Write-Host ""; Write-Host "  $Text" -ForegroundColor Cyan }
function Write-Ok   { param($Text) Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Warn { param($Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Err  { param($Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Info { param($Text) Write-Host "         $Text" -ForegroundColor DarkGray }

$script:Problems = @()
$script:Warnings = @()

function Add-Problem { param($Title, $Reason, $Fix) $script:Problems += ([PSCustomObject]@{ Title = $Title; Reason = $Reason; Fix = $Fix }) }
function Add-Warning { param($Title, $Reason, $Fix) $script:Warnings += ([PSCustomObject]@{ Title = $Title; Reason = $Reason; Fix = $Fix }) }

# ------------------------------------------------------------------ 通用工具
function Resolve-Tool {
    param(
        [string]$Name,
        [string[]]$ExtraDirs = @(),
        [string]$EnvVar = ''
    )
    # 1) 环境变量显式指定
    if ($EnvVar) {
        $v = [Environment]::GetEnvironmentVariable($EnvVar)
        if ($v) {
            if (Test-Path -LiteralPath $v -PathType Leaf) { return $v }
        }
    }
    # 2) PATH
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # 3) 常见安装目录
    foreach ($d in $ExtraDirs) {
        if (-not $d) { continue }
        $p = Join-Path $d "$Name.exe"
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}

function Add-ToPath {
    param([string]$ExePath)
    if (-not $ExePath) { return }
    $d = Split-Path -Parent $ExePath
    if ($d -and ($env:PATH -notlike "*$d*")) { $env:PATH = "$d;$env:PATH" }
}

function Test-PortOpen {
    param([int]$Port)
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return ($null -ne $c)
}

function Stop-PortOwner {
    param([int]$Port)
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if ($p -and $p.Id -ne $PID) {
            Write-Info "结束端口 $Port 上的进程 $($p.ProcessName) (PID $($p.Id))"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-Http {
    param([string]$Url)
    # 直接用 .NET 发请求：不依赖 Invoke-WebRequest，也不会在非交互宿主里刷错误提示
    try {
        $req = [System.Net.HttpWebRequest]::CreateHttp($Url)
        $req.Method  = 'GET'
        $req.Timeout = 3000
        $resp = $req.GetResponse()
        try { return ([int]$resp.StatusCode -eq 200) } finally { $resp.Close() }
    } catch { return $false }
}

# ------------------------------------------------------------------ 标题
Clear-Host
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor DarkCyan
Write-Host "     墨排 · LaTeX Studio     本地一键启动" -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor DarkCyan

# ------------------------------------------------------------------ 1. 工具链
Write-Head "步骤 1 / 5   检查工具链"

# ---- Python
$script:PyExe = $null
if (Test-Path -LiteralPath $venvPy -PathType Leaf) {
    $script:PyExe = $venvPy
    Write-Ok "Python 虚拟环境：agent\.venv"
} else {
    $py = Resolve-Tool 'python'
    if (-not $py) {
        # py 启动器：解析成真实的 python.exe，避免后续参数传递问题
        $launcher = Resolve-Tool 'py'
        if ($launcher) {
            $resolved = (& $launcher -3 -c 'import sys;print(sys.executable)' 2>$null | Select-Object -First 1)
            if ($resolved -and (Test-Path -LiteralPath $resolved -PathType Leaf)) { $py = $resolved }
        }
    }
    if ($py) {
        $script:PyExe = $py
        $ver = (& $py -c 'import sys;print(sys.version.split()[0])' 2>$null | Select-Object -First 1)
        Write-Ok "Python：$ver  （$py）"
    } else {
        Write-Err "未找到 Python"
        Add-Problem 'Python' 'PATH 中没有 python，也没有 py 启动器' '到 https://www.python.org/downloads/ 安装 3.10 及以上版本，安装时勾选 "Add Python to PATH"'
    }
}

<#
    用退出码判断 import 是否成功。
    注意：不能用 python -c "...print('ok')" 再比对 stdout ——
    Windows PowerShell 5.1 传给原生命令的参数会吞掉内部引号，结果必然误判。
#>
function Test-PythonImport {
    param([string]$ImportLine)
    if (-not $script:PyExe) { return $false }
    & $script:PyExe -c $ImportLine 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ---- Pandoc（DOCX / Markdown / TXT 转换依赖）
$pandoc = Resolve-Tool 'pandoc' @(
    'C:\Program Files\Pandoc',
    'C:\Program Files (x86)\Pandoc',
    (Join-Path $env:LOCALAPPDATA 'Pandoc')
) 'PANDOC_PATH'
if ($pandoc) {
    Add-ToPath $pandoc
    $pv = (& $pandoc --version 2>$null | Select-Object -First 1)
    Write-Ok "Pandoc：$pv  （$pandoc）"
} else {
    Write-Warn "Pandoc 未找到 —— DOCX / Markdown 将无法转换"
    Add-Warning 'Pandoc' '没有检测到 pandoc，DOCX / MD / TXT 转换会直接报错' 'https://github.com/jgm/pandoc/releases 下载 pandoc-*-windows-x86_64.msi 安装；或设置环境变量 PANDOC_PATH 指向 pandoc.exe'
}

# ---- TeX 发行版（生成 PDF 依赖）
$texDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\MiKTeX\miktex\bin\x64'),
    'C:\Program Files\MiKTeX\miktex\bin\x64',
    'C:\Program Files (x86)\MiKTeX\miktex\bin\x64',
    (Join-Path $env:ProgramData 'MiKTeX\miktex\bin\x64')
)
foreach ($y in 2026..2019) { $texDirs += "C:\texlive\$y\bin\windows" }

$latexmk = Resolve-Tool 'latexmk' $texDirs 'LATEXMK_BIN'
$xelatex = Resolve-Tool 'xelatex' $texDirs 'XELATEX_PATH'
if ($latexmk) { Add-ToPath $latexmk; Write-Ok "latexmk：$latexmk" }
else          { Write-Warn "latexmk 未找到 —— 将自动改用 xelatex 直接编译" }

if ($xelatex) {
    Add-ToPath $xelatex
    Write-Ok "xelatex：$xelatex"
} else {
    Write-Err "xelatex 未找到 —— 无法生成 PDF，只能得到 .tex 源码"
    Add-Warning 'TeX 发行版' '没有检测到 xelatex，编译环节必然失败' 'Windows 推荐 MiKTeX https://miktex.org/download ；装完打开 MiKTeX Console 执行一次 Tasks → Update，并把 "Always install missing packages on the fly" 设为 Yes'
}

# ---- Perl（MiKTeX 的 latexmk 是 Perl 脚本）
$perl = Resolve-Tool 'perl' @('C:\Strawberry\perl\bin', 'C:\Strawberry\c\bin', 'C:\Perl64\bin')
if ($perl) {
    Add-ToPath $perl
    Write-Ok "Perl：$perl"
} elseif ($latexmk) {
    Write-Warn "Perl 未安装，latexmk 可能无法执行（程序会自动回退为直接调用 xelatex）"
    Add-Warning 'Perl' 'MiKTeX 附带的 latexmk 是 Perl 脚本，缺 Perl 时会报 could not find the script engine' '可选：https://strawberryperl.com/ 安装 Strawberry Perl；不装也能用，程序会自动改用 xelatex'
}

# ------------------------------------------------------------------ 2. Python 依赖
Write-Head "步骤 2 / 5   检查 Python 依赖"
$depsOk = $false
$CORE_IMPORT = 'import fastapi,uvicorn,httpx,pydantic,PIL'
$FULL_IMPORT = 'import fitz,docx'

if ($script:PyExe) {
    if ((Test-PythonImport $CORE_IMPORT) -and (Test-PythonImport 'import multipart')) {
        $depsOk = $true
        Write-Ok "核心依赖已就绪（fastapi / uvicorn / httpx / pydantic / Pillow）"
        if (-not (Test-PythonImport $FULL_IMPORT)) {
            Write-Warn "可选依赖缺失（PyMuPDF / python-docx）—— PDF 与 DOCX 相关功能会受影响"
        }
    } else {
        Write-Warn "核心依赖缺失，自动安装…"
        if (-not (Test-Path -LiteralPath $venvPy -PathType Leaf)) {
            Write-Info "创建虚拟环境 agent\.venv"
            & $script:PyExe -m venv (Join-Path $agentDir '.venv') 2>&1 | Out-Null
            if (Test-Path -LiteralPath $venvPy -PathType Leaf) { $script:PyExe = $venvPy }
        }
        if (-not (Test-Path -LiteralPath $reqFile -PathType Leaf)) {
            Write-Err "找不到 agent\requirements.txt"
            Add-Problem '依赖清单' "文件不存在：$reqFile" '重新下载完整的项目源码'
        } else {
            Write-Info "pip install -r requirements.txt（首次需要联网，请稍候）"
            & $script:PyExe -m pip install -r $reqFile 2>&1 | Select-Object -Last 4
            if (-not (Test-PythonImport $CORE_IMPORT)) {
                Write-Info "默认源失败，改用清华镜像重试…"
                & $script:PyExe -m pip install -r $reqFile -i https://pypi.tuna.tsinghua.edu.cn/simple 2>&1 | Select-Object -Last 4
            }
            if (Test-PythonImport $CORE_IMPORT) { $depsOk = $true; Write-Ok "依赖安装完成" }
        }
    }
}
if (-not $depsOk) {
    Write-Err "Python 依赖无法满足"
    Add-Problem 'Python 依赖' 'pip 安装失败，或安装后仍有核心包缺失' "手动执行：`n           $script:PyExe -m pip install -r agent\requirements.txt`n           国内网络可加 -i https://pypi.tuna.tsinghua.edu.cn/simple"
}

# ------------------------------------------------------------------ 3. 端口
Write-Head "步骤 3 / 5   检查端口"
if (-not (Test-Path -LiteralPath $distDir -PathType Container)) {
    Write-Err "找不到 dist 目录（静态工作台页面缺失）"
    Add-Problem '静态工作台' "目录不存在：$distDir" '重新下载完整源码；或执行 python scripts\package.py 重新生成'
}
foreach ($p in @($AGENT_PORT, $COMPILER_PORT, $WEB_PORT)) {
    if (Test-PortOpen $p) {
        if ($Reset) {
            Stop-PortOwner $p
            Start-Sleep -Seconds 1
        } else {
            Write-Warn "端口 $p 已被占用 —— 将直接复用现有服务（如需重启请加 -Reset）"
        }
    } else {
        Write-Ok "端口 $p 空闲"
    }
}

# ------------------------------------------------------------------ 4. 启动服务
Write-Head "步骤 4 / 5   启动服务"
if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$compilerLog = Join-Path $logDir 'compiler.log'
$agentLog    = Join-Path $logDir 'agent.log'
$webLog      = Join-Path $logDir 'web.log'

$env:COMPILER_TOKEN  = $COMPILER_TOKEN
$env:AGENT_TOKEN     = $AGENT_TOKEN
$env:ALLOWED_ORIGINS = "$WEB_URL,http://127.0.0.1:$WEB_PORT"
$env:COMPILER_URL    = $COMPILER_URL
$env:DATA_DIR        = Join-Path $agentDir 'jobs'
if ($pandoc)  { $env:PANDOC_PATH  = $pandoc }
if ($latexmk) { $env:LATEXMK_BIN  = $latexmk }
if ($xelatex) { $env:XELATEX_PATH = $xelatex }

function Start-Service {
    param($Name, $WorkingDir, [string[]]$Arguments, $LogFile)
    if (-not (Test-Path -LiteralPath $WorkingDir -PathType Container)) {
        Write-Err "$Name 启动失败：工作目录不存在 $WorkingDir"
        return $false
    }
    if (-not $script:PyExe) { Write-Err "$Name 启动失败：未找到可用的 Python"; return $false }
    # 清掉上一轮的日志（用 .NET 直接删，避免依赖 Remove-Item 的行为差异）
    foreach ($f in @($LogFile, "$LogFile.err")) {
        try { if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) } } catch {}
    }
    try {
        Start-Process -FilePath $script:PyExe `
            -ArgumentList $Arguments `
            -WorkingDirectory $WorkingDir `
            -RedirectStandardOutput $LogFile `
            -RedirectStandardError "$LogFile.err" `
            -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Write-Info "$Name 已启动，日志 $LogFile"
        return $true
    } catch {
        Write-Err "$Name 启动失败：$($_.Exception.Message)"
        return $false
    }
}

$needAgent    = -not (Test-Http "$AGENT_URL/health")
$needCompiler = -not (Test-Http "$COMPILER_URL/health")
$needWeb      = -not (Test-Http "http://127.0.0.1:$WEB_PORT/index.html")

if ($needCompiler) {
    $ok = Start-Service '编译服务' $agentDir @('-m', 'uvicorn', 'compiler:app', '--host', '127.0.0.1', '--port', "$COMPILER_PORT") $compilerLog
    if (-not $ok) { Add-Problem '编译服务' '进程启动失败' "查看日志 $compilerLog 与 $compilerLog.err" }
} else { Write-Ok "编译服务已在运行（端口 $COMPILER_PORT）" }

if ($needAgent) {
    $ok = Start-Service 'Agent 服务' $agentDir @('-m', 'uvicorn', 'server:app', '--host', '127.0.0.1', '--port', "$AGENT_PORT") $agentLog
    if (-not $ok) { Add-Problem 'Agent 服务' '进程启动失败' "查看日志 $agentLog 与 $agentLog.err" }
} else { Write-Ok "Agent 服务已在运行（端口 $AGENT_PORT）" }

if ($needWeb) {
    $ok = Start-Service '静态工作台' $distDir @('-m', 'http.server', "$WEB_PORT", '--bind', '127.0.0.1') $webLog
    if (-not $ok) { Add-Problem '静态工作台' '进程启动失败' "查看日志 $webLog 与 $webLog.err" }
} else { Write-Ok "静态工作台已在运行（端口 $WEB_PORT）" }

# ------------------------------------------------------------------ 5. 健康检查
Write-Head "步骤 5 / 5   健康检查"
$ready = @{ Agent = $false; Compiler = $false; Web = $false }
foreach ($i in 1..30) {
    Start-Sleep -Seconds 1
    if (-not $ready.Agent)    { $ready.Agent    = Test-Http "$AGENT_URL/health" }
    if (-not $ready.Compiler) { $ready.Compiler = Test-Http "$COMPILER_URL/health" }
    if (-not $ready.Web)      { $ready.Web      = Test-Http "http://127.0.0.1:$WEB_PORT/index.html" }
    if ($ready.Agent -and $ready.Compiler -and $ready.Web) { break }
}

if ($ready.Agent)    { Write-Ok "Agent 服务    $AGENT_URL" }
else                 { Write-Err "Agent 服务未就绪";    Add-Problem 'Agent 服务'    '30 秒内 /health 未返回 200' "查看日志 $agentLog / $agentLog.err；常见原因是依赖缺失或端口被占用" }
if ($ready.Compiler) { Write-Ok "编译服务      $COMPILER_URL" }
else                 { Write-Err "编译服务未就绪";   Add-Problem '编译服务'   '30 秒内 /health 未返回 200' "查看日志 $compilerLog / $compilerLog.err" }
if ($ready.Web)      { Write-Ok "静态工作台    $WEB_URL" }
else                 { Write-Err "静态工作台未就绪"; Add-Problem '静态工作台' '30 秒内首页未返回 200' "确认 dist\index.html 存在；查看日志 $webLog" }

$agentHealth = $null
if ($ready.Agent) {
    try { $agentHealth = (Invoke-WebRequest "$AGENT_URL/health" -UseBasicParsing -TimeoutSec 5).Content | ConvertFrom-Json } catch {}
}

# ------------------------------------------------------------------ 结果
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor DarkCyan

$allOk = ($script:Problems.Count -eq 0) -and $ready.Agent -and $ready.Web

if ($allOk) {
    $pandocTxt = if ($agentHealth -and $agentHealth.pandoc) { '已就绪' } else { '未安装 —— DOCX / MD 不可用' }
    $latexTxt  = if ($xelatex) { '已就绪' } else { '未安装 —— 无法生成 PDF' }
    $perlTxt   = if ($perl) { '已安装' } elseif ($latexmk) { '未安装，已自动回退直调引擎' } else { '未安装' }
    $warnRows  = ''
    foreach ($w in $script:Warnings) {
        $warnRows += "<tr><td>$($w.Title)</td><td>$($w.Reason) <span style='color:#9aa39a'>$($w.Fix)</span></td></tr>`n"
    }
    if ($warnRows) { $warnBlock = "<h2>需要注意</h2><table>$warnRows</table>" } else { $warnBlock = '' }

    $html = @"
<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>墨排 · LaTeX Studio 已启动</title>
<style>
*{box-sizing:border-box}
body{margin:0;font-family:"Microsoft YaHei","PingFang SC",system-ui,sans-serif;background:#f6f7f4;color:#2f3b2f;padding:44px 18px}
.wrap{max-width:760px;margin:auto;background:#fff;border:1px solid #e2e5df;border-radius:14px;padding:38px 42px}
h1{font-size:26px;margin:0 0 4px;font-weight:600}
.sub{color:#7d8a7d;font-size:14px;margin:0 0 22px}
.badge{display:inline-block;background:#eaf3ea;color:#3d7a3d;border:1px solid #cfe3cf;border-radius:999px;padding:5px 14px;font-size:13px;margin-bottom:24px}
a.btn{display:inline-block;background:#3f6b3f;color:#fff;text-decoration:none;padding:14px 28px;border-radius:9px;font-size:16px}
a.btn:hover{background:#335733}
h2{font-size:15px;margin:32px 0 10px;color:#4a554a;font-weight:600}
table{width:100%;border-collapse:collapse;font-size:14px}
td{padding:11px 4px;border-bottom:1px solid #eef0ec;vertical-align:top;word-break:break-all}
td:first-child{color:#7d8a7d;width:132px;white-space:nowrap}
code{background:#f2f4f0;padding:2px 7px;border-radius:4px;font-size:13px}
a{color:#3f6b3f}
.tip{margin-top:28px;font-size:13px;color:#7d8a7d;line-height:2}
</style></head>
<body><div class="wrap">
<h1>墨排 · LaTeX Studio</h1>
<p class="sub">本地服务已全部就绪</p>
<span class="badge">启动成功</span><br>
<a class="btn" href="$WEB_URL" target="_blank">打开排版工作台 &rarr;</a>
<h2>访问地址</h2>
<table>
<tr><td>工作台</td><td><a href="$WEB_URL">$WEB_URL</a></td></tr>
<tr><td>接口文档</td><td><a href="http://localhost:$AGENT_PORT/docs">http://localhost:$AGENT_PORT/docs</a></td></tr>
<tr><td>Agent 地址</td><td><code>http://localhost:$AGENT_PORT</code></td></tr>
<tr><td>Agent Token</td><td><code>$AGENT_TOKEN</code></td></tr>
</table>
<h2>工具链状态</h2>
<table>
<tr><td>Pandoc</td><td>$pandocTxt</td></tr>
<tr><td>TeX</td><td>$latexTxt</td></tr>
<tr><td>Perl</td><td>$perlTxt</td></tr>
</table>
$warnBlock
<p class="tip">
工作台右上角「模型设置」里填：Agent 地址 <code>http://localhost:$AGENT_PORT</code>，Token <code>$AGENT_TOKEN</code>。<br>
不配置模型也能处理 DOCX / TeX / ZIP；只有 PDF 与图片识别才需要视觉大模型。<br>
停止服务：回到启动窗口按 <code>Q</code> 回车，或运行 <code>scripts\stop.ps1</code>。
</p>
</div></body></html>
"@
    $report = Join-Path $env:TEMP 'mopai-launch.html'
    [System.IO.File]::WriteAllText($report, $html, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "     启动成功" -ForegroundColor Green
    Write-Host ""
    Write-Host "     工作台：      $WEB_URL" -ForegroundColor Yellow
    Write-Host "     接口文档：    http://localhost:$AGENT_PORT/docs"
    Write-Host "     Agent Token： $AGENT_TOKEN"
    Write-Host ""
    if ($script:Warnings.Count -gt 0) {
        Write-Host "     注意（不影响启动）：" -ForegroundColor Yellow
        foreach ($w in $script:Warnings) { Write-Host "       - $($w.Title)：$($w.Reason)" -ForegroundColor Yellow }
        Write-Host ""
    }
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host ""

    if (-not $NoBrowser) {
        try {
            Start-Process $report
            Start-Sleep -Milliseconds 800
            Start-Process $WEB_URL
        } catch {
            Write-Warn "无法自动打开浏览器，请手动访问 $WEB_URL"
        }
    } else {
        Write-Host "     （-NoBrowser：未自动打开浏览器）" -ForegroundColor DarkGray
    }

    if (-not $Detached) {
        Write-Host "     服务在后台运行中。按 Q + 回车停止全部服务，或直接关闭本窗口（服务继续运行）。" -ForegroundColor DarkGray
        while ($true) {
            $k = (Read-Host).Trim()
            if ($k -eq 'q' -or $k -eq 'Q') {
                Write-Info "正在停止服务…"
                foreach ($p in @($AGENT_PORT, $COMPILER_PORT, $WEB_PORT)) { Stop-PortOwner $p }
                Write-Ok "已停止"
                break
            }
        }
    }
    exit 0
} else {
    Write-Host "     启动未完全成功" -ForegroundColor Red
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    foreach ($p in $script:Problems) {
        Write-Host "  - $($p.Title)" -ForegroundColor Red
        Write-Host "      原因：$($p.Reason)" -ForegroundColor White
        Write-Host "      处理：$($p.Fix)" -ForegroundColor DarkGray
        Write-Host ""
    }
    if ($script:Warnings.Count -gt 0) {
        Write-Host "  其他提示：" -ForegroundColor Yellow
        foreach ($w in $script:Warnings) {
            Write-Host "  - $($w.Title)：$($w.Reason)" -ForegroundColor Yellow
            Write-Host "      $($w.Fix)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    exit 1
}
