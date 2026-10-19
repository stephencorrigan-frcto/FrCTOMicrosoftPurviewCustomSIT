cat <<EOF > /etc/pricing.conf
mode=production
port=8080
EOF
systemctl restart pricing