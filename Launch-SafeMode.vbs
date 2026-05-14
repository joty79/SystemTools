' Elevated wrapper for SafeMode.ps1
' Runs with admin rights via wt

Dim scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

Set objShell = CreateObject("Shell.Application")
args = "new-tab pwsh -ExecutionPolicy Bypass -File """ & scriptDir & "SafeMode.ps1"""
objShell.ShellExecute "wt.exe", args, "", "runas", 1
