Connect-AzAccount -Identity | Out-Null
Get-AzVM -ResourceGroupName 'rg-pricing' | Where-Object PowerState -eq 'VM running' | Stop-AzVM -Force