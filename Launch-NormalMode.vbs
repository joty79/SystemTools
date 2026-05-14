' Elevated wrapper for NormalMode.ps1
' Uses pwsh directly (wt doesn't work in Safe Mode)

Dim scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

Set objShell = CreateObject("Shell.Application")
args = "-ExecutionPolicy Bypass -File """ & scriptDir & "NormalMode.ps1"""
objShell.ShellExecute "pwsh.exe", args, "", "runas", 1
