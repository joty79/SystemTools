Dim shell, scriptPath, targetPath, command

Set shell = CreateObject("WScript.Shell")

scriptPath = "D:\Users\joty79\scripts\SystemTools\RestartExplorer.ps1"
targetPath = ""

If WScript.Arguments.Count > 0 Then
    targetPath = Replace(WScript.Arguments(0), """", """""")
End If

command = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -TargetPath """ & targetPath & """ -ReopenFolder -NoPause"
shell.Run command, 0, False
