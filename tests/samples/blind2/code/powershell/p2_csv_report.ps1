$report = foreach ($s in Get-Service) { [pscustomobject]@{ Name = $s.Name; Status = $s.Status } }
$report | Export-Csv -Path .\services.csv -NoTypeInformation