Option Explicit

If WScript.Arguments.Count = 0 Then
    WScript.Quit 1
End If

Dim targetPath
targetPath = WScript.Arguments(0)
targetPath = Replace(targetPath, """", """""")

Dim scriptPath
scriptPath = "D:\Users\joty79\scripts\SystemTools\AddDelPath.ps1"

Dim wtArgs
wtArgs = "-w 0 nt --title ""System-Tools-PATH-Admin"" pwsh.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -Action Menu -TargetPath """ & targetPath & """ -SkipWtBootstrap -NoPause"

CreateObject("Shell.Application").ShellExecute "wt.exe", wtArgs, "", "runas", 1
