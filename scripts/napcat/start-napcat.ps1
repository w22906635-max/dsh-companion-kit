# NapCat 启动器（脱离 DSH 独立运行）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File start-napcat.ps1
#   powershell -ExecutionPolicy Bypass -File start-napcat.ps1 -NapCatDir 'D:\NapCat' -QQAccount '123456789'
#
# 登录顺序：先试「密码快速登录」（读 $NapCatDir\napcat-pw.txt），没有密码文件就出二维码。
# 密码文件里可以放明文，也可以放 32 位 MD5（推荐 —— 磁盘上不留明文）。

param(
    [string]$NapCatDir = 'D:\NapCat',
    [string]$QQAccount = '',
    [int]$WebUiPort = 6099
)

$ErrorActionPreference = 'Continue'

# 配置文件（同目录的 napcat.conf.json）优先于命令行参数
. (Join-Path $PSScriptRoot '_config.ps1')
$c = Get-NapCatConfig -Dir $NapCatDir -Account $QQAccount -OneBot 3000 -WebUi $WebUiPort -ConfigPath (Join-Path $PSScriptRoot 'napcat.conf.json')
$NapCatDir = $c.NapCatDir
$QQAccount = $c.QQAccount
$WebUiPort = $c.WebUiPort

$log = Join-Path $NapCatDir 'napcat-autostart.log'
function W($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -LiteralPath $log -Encoding utf8 }

try {
    # 已经在跑（WebUI 端口在听）就不重复启动
    $busy = Get-NetTCPConnection -LocalPort $WebUiPort -State Listen -ErrorAction SilentlyContinue
    if ($busy) { W 'NapCat 已在运行（WebUI 端口在听），跳过'; exit 0 }

    $pwFile = Join-Path $NapCatDir 'napcat-pw.txt'
    $argList = @('index.js', '-q')
    if ($QQAccount) { $argList += $QQAccount }

    if (Test-Path $pwFile) {
        $pw = (Get-Content -LiteralPath $pwFile -Raw -ErrorAction SilentlyContinue)
        if ($pw) { $pw = $pw.Trim().TrimStart([char]0xFEFF).Trim() }
        if ($pw) {
            if ($QQAccount) { $env:ACCOUNT = $QQAccount }
            if ($pw -match '^[0-9a-fA-F]{32}$') {
                # 直接填密码的 MD5 也行 —— 这样磁盘上就没有明文密码
                $env:NAPCAT_QUICK_PASSWORD_MD5 = $pw
                W '使用密码快速登录（MD5 形式，磁盘上无明文）'
            } else {
                $env:NAPCAT_QUICK_PASSWORD = $pw
                W '使用密码快速登录（明文形式）'
            }
        } else {
            W '密码文件是空的 → 走扫码登录'
        }
    } else {
        W '没有密码文件 → 走扫码登录'
    }

    Start-Process -FilePath (Join-Path $NapCatDir 'node.exe') `
        -ArgumentList $argList `
        -WorkingDirectory $NapCatDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $NapCatDir 'napcat-out.log') `
        -RedirectStandardError (Join-Path $NapCatDir 'napcat-err.log')

    W '已拉起 napcat（隐藏窗口，输出见 napcat-out.log）'
} catch {
    W ('启动失败：' + $_.Exception.Message)
}
