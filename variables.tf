variable "internal_domain" {
  description = "Private DNS domain for VPC"
  # example = "example.com"
}

variable "letsencrypt_email_address" {
  description = "Email address for emails from Let's Encrypt"
  # example = "example@example.com"
}

variable "aws_region" {
  description = "AWS region"
  # example = "eu-west-1"
}

variable "vpc_cidr_block" {
  description = "AWS VPC CIDR block"
  # example = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "AWS public subnet CIDR block"
  # example = "10.1.0.0/24"
}

variable "public_subnet_az" {
  description = "AWS VPC availability zone (AZ)"
  # example = "eu-west-1a"
}

variable "key_pair_public_key" {
  description = "SSH public key"
  # example = "ssh-ed25519 1234 example@example.com
}

variable "wireguard_instance_type" {
  description = "Type of EC2 instance to provision"
  # example = "t2.micro"
}

variable "wireguard_cpu_credits" {
  description = "Credit option for CPU usage"
  # example = "standard"
}

variable "wireguard_peer_cidr_blocks" {
  description = "Public CIDR blocks for WireGuard peers"
  # example = ["1.2.3.4/32"]
}

variable "argocd_ip_allowlist" {
  description = "IP allowlist for accessing Argo CD server"
  # example = "10.1.1.0/24"
}

variable "wireguard_address" {
  description = "WireGuard server address"
  # example = "10.2.1.1/32"
}

variable "wireguard_listen_port" {
  description = "WireGuard UDP port"
  # example = 1234
}

variable "wireguard_private_key" {
  description = "WireGuard private key"
  # example = "do-not-use-this-value"
}

variable "wireguard_peers" {
  description = "WireGuard VPN peers"
  # example = [{ public_key = "do-not-use-this-value", allowed_ips = "10.2.1.2/32" }]
}

variable "microk8s_instance_type" {
  description = "Type of EC2 instance to provision"
  # example = "t2.micro"
}

variable "microk8s_cpu_credits" {
  description = "Credit option for CPU usage"
  # example = "standard"
}
