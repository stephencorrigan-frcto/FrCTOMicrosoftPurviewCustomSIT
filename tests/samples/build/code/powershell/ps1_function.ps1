function Get-StaleFiles {
    [CmdletBinding()]
    param([string]$Path, [int]$Days = 30)
    Get-ChildItem -Path $Path -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Days) }
}