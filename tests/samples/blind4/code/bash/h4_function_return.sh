is_up() { curl -sf "$1" >/dev/null; }
is_up http://localhost:8080 || systemctl restart pricing