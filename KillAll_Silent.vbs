' Silent wrapper for KillAll.ps1
' Runs the PowerShell script without showing any window

Set objShell = CreateObject("WScript.Shell")

Dim scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

command = "pwsh.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptDir & "KillAll.ps1"""

' Run silently (0 = hidden, False = don't wait)
objShell.Run command, 0, False
