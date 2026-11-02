# NapCat 看门狗 v2
#
# 判三种情况：
#   ① 3000 通              → 健康，什么都不做
#   ② 3000/6099 都不通     → 进程没了 → 直接拉起
#   ③ 3000 不通但 6099 通  → 进程在、没登录（卡二维码循环）→ 等够时间再重启一次
#
# ③ 有退避保护：15 → 30 → 60 分钟；连续 3 次重启都没登上就停手，
#    只在日志里留一句「需要人工扫码」，免得每 5 分钟把用户要扫的码杀掉。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File watchdog.ps1 -NapCatDir 'D:\NapCat' -QQAccount '123456789'

param(
    [string]$NapCatDir = 'D:\NapCat',
    [string]$QQAccount = '',
    [int]$OneBotPort = 3000,
    [int]$WebUiPort = 6099
)

$log = Join-Path $NapCatDir 'napcat-watchdog.log'
$stateFile = Join-Path $NapCatDir 'watchdog-state.json'
$startScript = Join-Path $PSScriptRoot 'start-napcat.ps1'

# 配置文件优先
. (Join-Path $PSScriptRoot '_config.ps1')
$c = Get-NapCatConfig -Dir $NapCatDir -Account $QQAccount -OneBot $OneBotPort -WebUi $WebUiPort -ConfigPath (Join-Path $PSScriptRoot 'napcat.conf.json')
$NapCatDir = $c.NapCatDir
$QQAccount = $c.QQAccount
$OneBotPort = $c.OneBotPort
$WebUiPort = $c.WebUiPort
$log = Join-Path $NapCatDir 'napcat-watchdog.log'
$stateFile = Join-Path $NapCatDir 'watchdog-state.json'

function W($m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -LiteralPath $log -Encoding utf8
}

function PortOk([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $p)
        $ok = $c.Connected
        $c.Close()
        return $ok
    } catch { return $false }
}

function SaveState($obj) {
    try { $obj | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding utf8 } catch {}
}

function KillNapCat {
    $pattern = $NapCatDir.TrimEnd('\') + '\*'
    Get-Process node -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like $pattern } |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

function StartNapCat {
    # ⚠ 必须显式带 -ExecutionPolicy Bypass：
    #   默认 Windows 执行策略是 Restricted，子进程不加这个会被直接拦下，
    #   表现是"日志写了要拉起，但什么都没发生"。
    $args = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $startScript, '-NapCatDir', $NapCatDir)
    if ($QQAccount) { $args += @('-QQAccount', $QQAccount) }
    & powershell.exe @args
}

$st = @{ lastRestartAt = 0; failures = 0 }
if (Test-Path $stateFile) {
    try {
        $raw = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $raw.lastRestartAt) { $st.lastRestartAt = [double]$raw.lastRestartAt }
        if ($null -ne $raw.failures) { $st.failures = [int]$raw.failures }
    } catch {}
}

$onebot = PortOk $OneBotPort
$webui = PortOk $WebUiPort

# ---------- ① 健康 ----------
if ($onebot) {
    if ($st.failures -ne 0) { $st.failures = 0; SaveState $st }
    exit 0
}

# ---------- ② 进程没了 ----------
if (-not $webui) {
    W 'NapCat 进程不在（OneBot / WebUI 都不通）→ 拉起'
    StartNapCat
    exit 0
}

# ---------- ③ 进程在、没登录 ----------
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$sinceMin = 99999
if ($st.lastRestartAt -gt 0) { $sinceMin = ($now - $st.lastRestartAt) / 60 }

if ($st.failures -ge 3) {
    # 已经试够了，别再动它（再动就是把用户要扫的二维码反复作废）
    if ($sinceMin -gt 720) {
        W '半通状态已超过 12 小时，重置计数（下次再试一轮）'
        $st.failures = 0; $st.lastRestartAt = 0; SaveState $st
    }
    exit 0
}

$waitMin = 15 * [Math]::Pow(2, [Math]::Min($st.failures, 2))   # 15 / 30 / 60
if ($sinceMin -lt $waitMin) { exit 0 }

if ($st.lastRestartAt -eq 0) {
    W ("半通（OneBot 不通 / WebUI 通）→ 首次发现，重启 NapCat 试快速登录（第 {0} 次）" -f ($st.failures + 1))
} else {
    W ("半通已 {0:N0} 分钟 → 重启 NapCat 试快速登录（第 {1} 次）" -f $sinceMin, ($st.failures + 1))
}
KillNapCat
Start-Sleep -Seconds 3
StartNapCat
Start-Sleep -Seconds 18

$st.lastRestartAt = $now
if (PortOk $OneBotPort) {
    $st.failures = 0
    W '重启后已登录 ✅'
} else {
    $st.failures = $st.failures + 1
    if ($st.failures -ge 3) {
        W '重启后仍未登录 ✗（连续 3 次）→ 停止自动重启，需要人工扫码'
    } else {
        W '重启后仍未登录 ✗，下次再试'
    }
}
SaveState $st
