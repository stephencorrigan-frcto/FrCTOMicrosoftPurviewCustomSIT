while IFS=, read -r sym qty; do
  echo "$sym has $qty"
done < trades.csv