Connect-MgGraph -Scopes "User.Read.All"
$users = Get-MgUser -All -Property DisplayName, AccountEnabled
$users | Where-Object { -not $_.AccountEnabled } | Measure-Object