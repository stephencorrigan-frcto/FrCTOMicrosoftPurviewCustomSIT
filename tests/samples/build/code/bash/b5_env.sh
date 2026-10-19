export API_URL="https://api.example.com"
if [[ -z "${TOKEN:-}" ]]; then echo "TOKEN not set" >&2; exit 1; fi
curl -s -H "Authorization: Bearer $TOKEN" "$API_URL/prices" > /dev/null 2>&1