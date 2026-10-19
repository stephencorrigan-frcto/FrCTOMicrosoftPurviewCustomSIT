backup() {
  local src="$1"
  local dest="$2"
  rsync -a "$src" "$dest" && echo "done" || echo "failed" >&2
}