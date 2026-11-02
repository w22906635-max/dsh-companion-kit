# 一键注册两个计划任务（登录自启 + 每 5 分钟看门狗）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File register-tasks.ps1
#
# 参数（路径、QQ 号、端口）统一写在 scripts/napcat/napcat.conf.json 里，
# 见同目录的 napcat.conf.example.json。
#
# 卸载：
#   Unregister-ScheduledTask -TaskName 'NapCat-Start' -Confirm:$false
#   Unregister-ScheduledTask -TaskName 'NapCat-Watchdog' -Confirm:$false

param(
    [string]$TaskPrefix = 'NapCat'
)

$ErrorActionPreference = 'Stop'

$napcatDir = Join-Path $PSScriptRoot 'napcat'
$vbs = Join-Path $napcatDir 'run-hidden.vbs'
if (-not (Test-Path $vbs)) { throw "找不到 $vbs，请先确认目录结构完整" }

$argStart = "//B //Nologo `"$vbs`" start-napcat.ps1"
$argWatch = "//B //Nologo `"$vbs`" watchdog.ps1"

Register-ScheduledTask -TaskName "$TaskPrefix-Start" `
    -Action (New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $argStart) `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
    -Force | Out-Null
Write-Host "✓ 已注册 $TaskPrefix-Start（登录时）"

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "$TaskPrefix-Watchdog" `
    -Action (New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $argWatch) `
    -Trigger $trigger `
    -Force | Out-Null
Write-Host "✓ 已注册 $TaskPrefix-Watchdog（每 5 分钟）"

Write-Host ''
Write-Host '别忘了先把 scripts\napcat\napcat.conf.example.json 复制成 napcat.conf.json 再改路径。'
