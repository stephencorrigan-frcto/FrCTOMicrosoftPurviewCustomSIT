[ -d /opt/pricing ] || mkdir -p /opt/pricing
[[ $EUID -ne 0 ]] && echo "run as root" && exit 1