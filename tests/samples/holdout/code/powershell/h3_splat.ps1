$params = @{
    Path        = 'C:\Reports'
    Filter      = '*.csv'
    ErrorAction = 'Stop'
}
Get-ChildItem @params