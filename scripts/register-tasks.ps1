# 注册自启与巡检
#
#   powershell -ExecutionPolicy Bypass -File register-tasks.ps1
#   powershell -ExecutionPolicy Bypass -File register-tasks.ps1 -Remove
#
# 两件事：
#   1. 每 5 分钟巡检的看门狗 —— 计划任务，不需要管理员
#   2. 登录时启动 —— 需要管理员（onlogon 触发器非管理员会「拒绝访问」）；
#      没有管理员时**自动改成在「启动」文件夹放一个快捷方式**，效果一样
#
# ⚠ 不要用 schtasks /tr 传带空格的路径：它会把路径劈成两半存进去
#   （实测 Execute=D:\AIwork、Arguments=space\...cmd）。用 Register-ScheduledTask 就不会。
#
# 路径、账号、端口统一写在 scripts/napcat/napcat.conf.json 里。

param(
    [string]$TaskPrefix = 'NapCat',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$napcatDir = Join-Path $PSScriptRoot 'napcat'
$vbs = Join-Path $napcatDir 'run-hidden.vbs'
if (-not (Test-Path $vbs)) { throw "找不到 $vbs，请先确认目录结构完整" }

$startArg = '//B //Nologo "' + $vbs + '" start-napcat.ps1'
$watchArg = '//B //Nologo "' + $vbs + '" watchdog.ps1'
$user = $env:USERNAME
$startupDir = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startupDir "$TaskPrefix-Start.lnk"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Remove) {
    foreach ($n in @("$TaskPrefix-Start", "$TaskPrefix-Watchdog")) {
        try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction Stop } catch {}
    }
    if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force }
    Write-Host "✓ 已删除任务与启动项（$TaskPrefix-*）"
    return
}

# ---- 1. 看门狗：每 5 分钟 ----
try {
    $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $watchArg
    $trg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName "$TaskPrefix-Watchdog" -Action $act -Trigger $trg -User $user -Force | Out-Null
    Write-Host "✓ $TaskPrefix-Watchdog（每 5 分钟）"
} catch {
    Write-Warning ("$TaskPrefix-Watchdog 注册失败：" + $_.Exception.Message)
}

# ---- 2. 登录自启 ----
if ($isAdmin) {
    try {
        $act2 = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $startArg
        Register-ScheduledTask -TaskName "$TaskPrefix-Start" -Action $act2 -Trigger (New-ScheduledTaskTrigger -AtLogOn) -User $user -Force | Out-Null
        Write-Host "✓ $TaskPrefix-Start（登录时，计划任务）"
    } catch {
        Write-Warning ("$TaskPrefix-Start 注册失败：" + $_.Exception.Message)
    }
} else {
    Write-Host '· 当前不是管理员 —— 改用「启动」文件夹放快捷方式（效果一样，不用提权）'
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = "$env:SystemRoot\System32\wscript.exe"
    $lnk.Arguments = $startArg
    $lnk.WorkingDirectory = $napcatDir
    $lnk.Description = 'NapCat 登录自启（dsh-companion-kit）'
    $lnk.Save()
    Write-Host "✓ 启动项：$lnkPath"
}

Write-Host ''
Write-Host '别忘了先把 napcat.conf.example.json 复制成 napcat.conf.json 再改路径。'
Write-Host ('验证：Get-ScheduledTask -TaskName "' + $TaskPrefix + '-*" | Select TaskName,State')
Write-Host '卸载：powershell -ExecutionPolicy Bypass -File register-tasks.ps1 -Remove'
