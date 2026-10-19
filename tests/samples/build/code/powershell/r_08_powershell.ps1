function Get-StaleFiles {
    param([string]$Path, [int]$Days = 30)
    foreach ($file in Get-ChildItem -Path $Path -Recurse) {
        if ($file.LastWriteTime -lt (Get-Date).AddDays(-$Days)) {
            Write-Output $file.FullName
        }
    }
}