variable "aws_region" {
  description = "AWS region"
  default = "us-west-1"
}

variable "vpc_cidr_block" {
  description = "AWS VPC CIDR block"
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "AWS public subnet CIDR block"
  default = "10.1.0.0/24"
}

variable "public_subnet_az" {
  description = "AWS VPC availability zone (AZ)"
  default = "us-west-1a"
}

variable "wireguard_instance_type" {
  description = "Type of EC2 instance to provision"
  default = "t2.micro"
}

variable "wireguard_cpu_credits" {
  description = "Credit option for CPU usage"
  default = "standard"
}

variable "wireguard_address" {
  description = "WireGuard server address"
  default = "10.2.0.0/24"
}

variable "wireguard_port" {
  description = "WireGuard UDP port"
  default = 1234
}

variable "wireguard_private_key" {
  description = "WireGuard private key"
  default = "change-me"
}

variable "wireguard_peers" {
  description = "WireGuard VPN peers"
  default = []
}

variable "microk8s_instance_type" {
  description = "Type of EC2 instance to provision"
  default = "t2.micro"
}

variable "microk8s_cpu_credits" {
  description = "Credit option for CPU usage"
  default = "standard"
}
