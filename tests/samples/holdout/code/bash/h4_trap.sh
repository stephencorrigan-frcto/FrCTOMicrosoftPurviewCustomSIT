cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT
TMPDIR=$(mktemp -d)