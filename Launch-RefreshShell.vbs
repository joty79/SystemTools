Dim shell, scriptPath, command

Set shell = CreateObject("WScript.Shell")

scriptPath = "D:\Users\joty79\scripts\SystemTools\RefreshShell.ps1"
command = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"

shell.Run command, 0, False
