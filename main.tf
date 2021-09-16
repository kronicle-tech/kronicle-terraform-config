provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "demo" {
  tags = {
    Name = "demo"
    terraform = "true"
  }

  cidr_block = var.vpc_cidr_block
}

resource "aws_subnet" "public" {
  tags = {
    Name = "public"
    terraform = "true"
  }

  vpc_id = aws_vpc.demo.id
  cidr_block = var.public_subnet_cidr_block
  availability_zone = var.public_subnet_az
}

resource "aws_internet_gateway" "main" {
  tags = {
    Name = "main"
    terraform = "true"
  }

  vpc_id = aws_vpc.demo.id
}

resource "aws_default_route_table" "default" {
  tags = {
    Name = "default"
    terraform = "true"
  }

  default_route_table_id = aws_vpc.demo.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

data "aws_ami" "ubuntu" {
  tags = {
    Name = "ubuntu"
    terraform = "true"
  }

  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-hirsute-21.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "main" {
  key_name   = "main"
  public_key = var.key_pair_public_key
}

resource "aws_iam_role" "ec2_cloudwatch_logging" {
  tags = {
    Name = "ec2_cloudwatch_logging"
    terraform = "true"
  }

  name               = "cloudwatch_logging"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Action": "sts:AssumeRole"
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow"
        "Sid": ""
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_logging" {
  name        = "cloudwatch_logging"
  path        = "/"
  description = "Allows sending logs to CloudWatch"

  policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        "Resource": [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ec2_cloudwatch_logging" {
  name       = "ec2_cloudwatch_logging"
  roles      = [aws_iam_role.ec2_cloudwatch_logging.name]
  policy_arn = aws_iam_policy.cloudwatch_logging.arn
}

resource "aws_iam_instance_profile" "cloudwatch_logging" {
  name  = "cloudwatch_logging"
  role = aws_iam_role.ec2_cloudwatch_logging.name
}

resource "aws_security_group" "ssh_public_subnet" {
  tags = {
    Name      = "ssh_public_subnet"
    terraform = "true"
  }

  description = "Allow instances in public subnet to connect to SSH port"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr_block]
  }
}

resource "aws_security_group" "wireguard_public_internet" {
  tags = {
    Name      = "wireguard_public_internet"
    terraform = "true"
  }

  description = "Allow traffic from internet from WireGuard peers"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port   = var.wireguard_listen_port
    to_port     = var.wireguard_listen_port
    protocol    = "udp"
    cidr_blocks = var.wireguard_peer_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wireguard_internal" {
  tags = {
    Name      = "wireguard_internal"
    terraform = "true"
  }

  description = "Allow traffic to internal resources from Wireguard peers"
  vpc_id      = aws_vpc.demo.id

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

resource "aws_launch_template" "wireguard" {
  tags = {
    Name = "wireguard"
    terraform = "true"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "wireguard"
      terraform = "true"
    }
  }

  name          = "wireguard"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.wireguard_instance_type
  key_name      = aws_key_pair.main.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.cloudwatch_logging.name
  }

  placement {
    availability_zone = var.public_subnet_az
  }

  network_interfaces {
    subnet_id                   = aws_subnet.public.id
    associate_public_ip_address = true
    security_groups             = [
      aws_security_group.ssh_public_subnet.id,
      aws_security_group.wireguard_public_internet.id,
      aws_security_group.wireguard_internal.id
    ]
  }

  credit_specification {
    cpu_credits = var.wireguard_cpu_credits
  }

  user_data = base64encode(templatefile("${path.cwd}/wireguard-install-script.sh.tpl", {
    aws_region = var.aws_region
    address = var.wireguard_address
    listen_port = var.wireguard_listen_port
    private_key = var.wireguard_private_key
    peers = var.wireguard_peers
  }))
}

resource "aws_autoscaling_group" "wireguard" {
  availability_zones = [var.public_subnet_az]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.wireguard.id
    version = "$Latest"
  }
}

resource "aws_eip" "microk8s" {
  vpc = true
}

resource "aws_security_group" "microk8s_public_subnet" {
  tags = {
    Name      = "microk8s_public_subnet"
    terraform = "true"
  }

  description = "Allow traffic from other private IP addresses in public subnet"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr_block]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "microk8s" {
  tags = {
    Name = "microk8s"
    terraform = "true"
  }

  tag_specifications {
    resource_type = "instance"
    
    tags = {
      Name = "microk8s"
      terraform = "true"
    }
  }

  name          = "microk8s"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.microk8s_instance_type
  key_name      = aws_key_pair.main.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.cloudwatch_logging.name
  }

  placement {
    availability_zone = var.public_subnet_az
  }

  network_interfaces {
    subnet_id       = aws_subnet.public.id
    associate_public_ip_address = true
    security_groups = [
      aws_security_group.ssh_public_subnet.id,
      aws_security_group.microk8s_public_subnet.id
    ]
  }

  credit_specification {
    cpu_credits = var.microk8s_cpu_credits
  }

  user_data = base64encode(templatefile("${path.cwd}/microk8s-install-script.sh.tpl", {
    internal_domain = var.internal_domain
    aws_region = var.aws_region
    microk8s_elastic_ip_id = aws_eip.microk8s.id
    public_subnet_cidr_block = var.public_subnet_cidr_block
  }))
}

resource "aws_autoscaling_group" "microk8s" {
  availability_zones = [var.public_subnet_az]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.microk8s.id
    version = "$Latest"
  }
}
