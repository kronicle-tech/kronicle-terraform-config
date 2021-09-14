#!/bin/bash

set -e

apt-get update -y
apt-get install -y wireguard

cat > /etc/wireguard/wg0.conf <<- EOF
[Interface]
Address = ${address}
ListenPort = ${port}
PrivateKey = ${private_key}
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

%{ for peer in peers ~}
[Peer]
PublicKey = ${peer.public_key}
AllowedIPs = ${peer.allowed_ips}
PersistentKeepalive = 25
%{ endfor ~}
EOF

chown -R root:root /etc/wireguard/
chmod -R og-rwx /etc/wireguard/*
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p
ufw allow ${port}/udp
ufw --force enable
systemctl enable wg-quick@wg0.service
systemctl start wg-quick@wg0.service
