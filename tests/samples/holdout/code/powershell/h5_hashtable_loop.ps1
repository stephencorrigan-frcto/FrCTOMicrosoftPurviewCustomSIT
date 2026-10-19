$counts = @{}
foreach ($line in Get-Content .\trades.csv) {
    $sym = ($line -split ',')[0]
    $counts[$sym]++
}