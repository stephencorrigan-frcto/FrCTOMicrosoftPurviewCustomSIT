#!/bin/bash
set -euo pipefail
for f in /tmp/test/*.log; do
  if [ -s "$f" ]; then
    echo "processing $f"
  fi
done