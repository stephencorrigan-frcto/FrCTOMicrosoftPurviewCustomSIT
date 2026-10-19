#!/bin/bash
set -euo pipefail
for f in /var/log/*.log; do
  if [ -s "$f" ]; then
    echo "processing $f"
    gzip "$f"
  fi
done