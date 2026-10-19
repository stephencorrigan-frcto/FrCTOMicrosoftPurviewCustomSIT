    $total = 0
    foreach ($row in $rows) { $total += [int]$row.Qty }
    if ($total -gt 1000) { Write-Warning "High volume: $total" }