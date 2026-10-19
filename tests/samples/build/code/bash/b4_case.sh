case "$1" in
  start) systemctl start pricing ;;
  stop)  systemctl stop pricing ;;
  *)     echo "usage: $0 start|stop"; exit 1 ;;
esac