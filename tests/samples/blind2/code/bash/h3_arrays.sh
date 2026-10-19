hosts=(web01 web02)
for h in "${hosts[@]}"; do ping -c1 "$h" > /dev/null && echo "$h up"; done