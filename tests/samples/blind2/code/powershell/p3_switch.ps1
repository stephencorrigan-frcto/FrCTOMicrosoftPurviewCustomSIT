switch -Regex ($line) {
    '^ERROR' { $errors++ }
    '^WARN'  { $warnings++ }
}