Option Explicit

Dim scriptPath
Dim targetItem
Dim safeTargetItem
Dim wtArgs

' FirewallMenu.ps1 lives in its own install directory (deployed by its own InstallerCore)
scriptPath = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\FirewallContext\FirewallMenu.ps1"

targetItem = ""
If WScript.Arguments.Count > 0 Then
    targetItem = WScript.Arguments(0)
End If
safeTargetItem = Replace(targetItem, """", """""")

If Len(targetItem) > 0 Then
    wtArgs = "--title ""Firewall Manager"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -TargetItem """ & safeTargetItem & """"
Else
    wtArgs = "--title ""Firewall Manager"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"
End If

CreateObject("Shell.Application").ShellExecute "wt.exe", wtArgs, "", "runas", 1
