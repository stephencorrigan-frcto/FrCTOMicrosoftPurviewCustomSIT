#!/bin/bash
for f in /var/log/*.log; do
  if [ -s "$f" ]; then
    echo "processing $f"
  fi
done