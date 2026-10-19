function Remove-OldReports {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    process {
        if ($PSCmdlet.ShouldProcess($Path)) { Remove-Item $Path -Force }
    }
}