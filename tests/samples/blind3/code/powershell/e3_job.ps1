$job = Start-Job -ScriptBlock { Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 }
Receive-Job $job -Wait