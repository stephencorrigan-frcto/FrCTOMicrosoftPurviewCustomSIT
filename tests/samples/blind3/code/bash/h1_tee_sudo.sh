echo "net.core.somaxconn=1024" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p