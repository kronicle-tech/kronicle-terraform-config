#!/bin/bash

set -e

# Send standard out and standard error to a log file that will be shipped to CloudWatch by the CloudWatch agent
exec > /var/log/user-data
exec 2>&1

echo '# Starting user-data script'

echo '# Updating packages metadata'
apt-get update -y

echo '# Installing AWS CLI'
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt-get install -y unzip
unzip awscliv2.zip
sudo ./aws/install

echo '# Disabling IPv6'
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

echo '# Associate Elastic IP'
aws ec2 associate-address --instance-id "$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)" --allocation-id ${elastic_ip_id}

echo '# Installing CloudWatch agent'
wget https://s3.${aws_region}.amazonaws.com/amazoncloudwatch-agent-${aws_region}/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
   "logs":{
      "logs_collected":{
         "files":{
            "collect_list":[
               {
                  "file_path":"/var/log/user-data",
                  "log_group_name":"wireguard",
                  "log_stream_name":"{instance_id}/var/log/user-data"
               }
            ]
         }
      }
   }
}
EOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo '# Installing WireGuard'
apt-get install -y wireguard

echo '# Creating WireGuard wg0 interface config file'
cat > /etc/wireguard/wg0.conf <<- EOF
[Interface]
Address = ${address}
ListenPort = ${listen_port}
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

echo '# Setting ownership and permissions for WireGuard config files'
chown -R root:root /etc/wireguard/
chmod -R og-rwx /etc/wireguard/*

echo '# Enabling IPv4 forwarding'
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

echo '# Configuring the firewall'
ufw allow ${listen_port}/udp
ufw --force enable

echo '# Starting WireGuard'
systemctl enable wg-quick@wg0.service
systemctl start wg-quick@wg0.service

echo '# Finished user-data script'
