Option Explicit

Dim shell, scriptPath, wtArgs

Set shell = CreateObject("Shell.Application")

scriptPath = "D:\Users\joty79\scripts\SystemTools\Clear-IconCache.ps1"
wtArgs = "-w new nt --title ""Clear-IconCache-Admin"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"

shell.ShellExecute "wt.exe", wtArgs, "", "runas", 1
