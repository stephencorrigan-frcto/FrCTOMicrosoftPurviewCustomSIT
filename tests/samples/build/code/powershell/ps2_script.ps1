$users = Import-Csv .\users.csv
foreach ($u in $users) {
    if ($u.Enabled -eq 'True') {
        Set-ADUser -Identity $u.Sam -Department $u.Dept
    }
}
Write-Output "Updated $($users.Count) users"