$users = Import-Csv .\users.csv
foreach ($u in $users) {
    if ($u.Enabled -eq 'True') {
        Write-Output "Processing $($u.Name)"
    }
}
Get-Service | Where-Object { $_.Status -eq 'Stopped' } | Select-Object Name