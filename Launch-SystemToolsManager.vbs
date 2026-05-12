Option Explicit

Dim scriptPath, wtArgs

scriptPath = "D:\Users\joty79\scripts\SystemTools\SystemToolsManager.ps1"
wtArgs = "-w new nt --title ""SystemTools-Manager"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"

CreateObject("Shell.Application").ShellExecute "wt.exe", wtArgs, "", "open", 1
