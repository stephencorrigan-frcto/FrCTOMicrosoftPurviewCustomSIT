try {
    $resp = Invoke-RestMethod -Uri $env:API_URL -Method Get
    $resp.items | ForEach-Object { $_.name }
} catch {
    Write-Error "Request failed: $($_.Exception.Message)"
}