$big = (Get-ChildItem -File).Where({ $_.Length -gt 1GB })
$big.Count