for host in web01 web02 web03; do
  ssh "$host" "sudo systemctl restart nginx"
done