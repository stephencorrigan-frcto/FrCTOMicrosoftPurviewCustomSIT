read -p "Environment? " env
[ "$env" = "prod" ] && confirm || echo "skipping"