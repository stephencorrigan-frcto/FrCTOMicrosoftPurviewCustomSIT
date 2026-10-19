Get-ChildItem -Path C:\Temp | Where-Object { $_.Length -gt 1MB } | Sort-Object Length
Write-Output "done"