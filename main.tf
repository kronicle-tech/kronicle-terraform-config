provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "demo" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "demo"
    "kronicle:terraform" = "true"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = "true"

  tags = {
    Name = "public"
    "kronicle:terraform" = "true"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "main"
    "kronicle:terraform" = "true"
  }
}

resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.demo.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "default"
    "kronicle:terraform" = "true"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "wireguard_public_internet" {
  description = "Allow traffic from internet from WireGuard peers"
  vpc_id      = aws_vpc.demo.id

  tags = {
    Name       = "wireguard_public_internet"
    "kronicle:terraform" = "true"
  }

  ingress {
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wireguard_internal" {
  description = "Allow traffic to internal resources from Wireguard peers"
  vpc_id      = aws_vpc.demo.id

  tags = {
    Name       = "wireguard_internal"
    "kronicle:terraform" = "true"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.wireguard_public_internet.id]
  }

  ingress {
    from_port       = 8
    to_port         = 0
    protocol        = "icmp"
    security_groups = [aws_security_group.wireguard_public_internet.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "wireguard" {
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = var.public_subnet_az
  subnet_id                   = aws_subnet.public.id
  instance_type               = var.wireguard_instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [
    aws_security_group.wireguard_public_internet.id, aws_security_group.wireguard_internal.id]

  credit_specification = {
    cpu_credits = var.wireguard_cpu_credits
  }

  tags = {
    Name = "wireguard"
    "kronicle:terraform" = "true"
  }

  user_data = templatefile("${path.cwd}/wireguard-install-script.sh.tpl", {
    cidr_block = var.wireguard_cidr_block,
    port = var.wireguard_port,
    private_key = var.wireguard_private_key,
    peers = var.wireguard_peers
  })
}

resource "aws_instance" "microk8s" {
  ami               = data.aws_ami.ubuntu.id
  availability_zone = var.public_subnet_az
  subnet_id         = aws_subnet.public.id
  instance_type     = var.microk8s_instance_type

  credit_specification = {
    cpu_credits = var.microk8s_cpu_credits
  }

  tags = {
    Name = "microk8s"
    "kronicle:terraform" = "true"
  }

  user_data = file("${path.cwd}/microk8s-install-script.sh")
}
