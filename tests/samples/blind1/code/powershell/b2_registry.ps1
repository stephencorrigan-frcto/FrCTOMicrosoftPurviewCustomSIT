$key = 'HKLM:\SOFTWARE\Contoso\Pricing'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name Mode -Value 'Prod'