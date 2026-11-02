' 用 wscript 启动一个 PowerShell 脚本，全程没有控制台窗口。
' wscript 是 GUI 子系统，所以桌面上不会闪黑框。
' 用法：wscript.exe //B //Nologo run-hidden.vbs watchdog.ps1

Option Explicit
Dim fso, shell, here, arg, script, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
arg = "watchdog.ps1"
If WScript.Arguments.Count > 0 Then arg = WScript.Arguments(0)
script = fso.BuildPath(here, arg)
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & script & """"
shell.Run cmd, 0, False
