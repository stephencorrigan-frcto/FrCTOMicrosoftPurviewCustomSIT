$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-File C:\Scripts\sync.ps1'
Register-ScheduledTask -TaskName 'Sync' -Action $action -RunLevel Highest