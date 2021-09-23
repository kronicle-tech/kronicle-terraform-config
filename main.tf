provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_vpc" "demo" {
  tags = {
    Name = "main"
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

resource "aws_route53_zone" "internal_domain" {
  tags = {
    Name      = "internal_domain"
    terraform = "true"
  }

  name = var.internal_domain
}

resource "aws_iam_role" "cert_manager" {
  tags = {
    Name      = "cert_manager"
    terraform = "true"
  }

  name               = "cert_manager"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": "sts:AssumeRole"
        "Principal": {
          "AWS": [
            aws_iam_role.microk8s.arn
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "cert_manager" {
  name        = "cert_manager"
  path        = "/"
  description = "Allows looking up and modifying a Route 53 zone"

  policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": "route53:GetChange"
        "Resource": "arn:aws:route53:::change/*"
      },
      {
        "Effect": "Allow"
        "Action": [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        "Resource": "arn:aws:route53:::hostedzone/*"
      },
      {
        "Effect": "Allow"
        "Action": "route53:ListHostedZonesByName"
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "cert_manager" {
  name       = "cert_manager"
  roles      = [aws_iam_role.cert_manager.name]
  policy_arn = aws_iam_policy.cert_manager.arn
}

resource "aws_iam_role" "external_secrets" {
  tags = {
    Name      = "external_secrets"
    terraform = "true"
  }

  name               = "external_secrets"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": "sts:AssumeRole"
        "Principal": {
          "AWS": [
            aws_iam_role.microk8s.arn
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "external_secrets" {
  name        = "external_secrets"
  path        = "/"
  description = "Allows retrieving certain secrets from Secrets Manager"

  policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ],
        "Resource": [
          "arn:aws:secretsmanager:${var.aws_region}:${local.aws_account_id}:secret:main/kronicle-service/*",
        ]
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "external_secrets" {
  name       = "external_secrets"
  roles      = [aws_iam_role.external_secrets.name]
  policy_arn = aws_iam_policy.external_secrets.arn
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

resource "aws_iam_policy" "associate_elastic_ip" {
  name        = "associate_elastic_ip"
  path        = "/"
  description = "Allows associating an Elastic IP with an EC2 instance"

  policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": [
          "ec2:AssociateAddress"
        ]
        "Resource": [
          "*"
        ]
      }
    ]
  })
}

resource "aws_eip" "wireguard" {
  vpc = true
}

resource "aws_iam_role" "wireguard" {
  tags = {
    Name      = "wireguard"
    terraform = "true"
  }

  name               = "wireguard"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": "sts:AssumeRole"
        "Principal": {
          "Service": "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "wireguard" {
  name  = "wireguard"
  role = aws_iam_role.wireguard.name
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
    name = aws_iam_instance_profile.wireguard.name
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
    elastic_ip_id = aws_eip.wireguard.id
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

resource "aws_iam_policy" "microk8s_elastic_ip" {
  name        = "microk8s_elastic_ip"
  path        = "/"
  description = "Allows associating an Elastic IP with an EC2 instance"

  policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": [
          "ec2:AssociateAddress"
        ]
        "Resource": [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "microk8s_route_53" {
  name        = "microk8s_route_53"
  path        = "/"
  description = "Allows changing Route 53 records in the internal domain zone"

  policy = jsonencode({
    "Version": "2012-10-17"
    "Statement":[
      {
        "Effect":"Allow"
        "Action": [
          "route53:ChangeResourceRecordSets"
        ]
        "Resource": [
          "arn:aws:route53:::hostedzone/${aws_route53_zone.internal_domain.zone_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "microk8s" {
  tags = {
    Name = "microk8s"
    terraform = "true"
  }

  name               = "microk8s"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17"
    "Statement": [
      {
        "Effect": "Allow"
        "Action": "sts:AssumeRole"
        "Principal": {
          "Service": "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "microk8s" {
  name  = "microk8s"
  role = aws_iam_role.microk8s.name
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    name = aws_iam_instance_profile.microk8s.name
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
    elastic_ip_id = aws_eip.microk8s.id
    hosted_zone_id = aws_route53_zone.internal_domain.zone_id
    zerossl_eab_kid = var.zerossl_eab_kid
    zerossl_eab_hmac_key = var.zerossl_eab_hmac_key
    letsencrypt_email_address = var.letsencrypt_email_address
    hosted_zone_id = aws_route53_zone.internal_domain.zone_id
    cert_manager_role = aws_iam_role.cert_manager.arn
    argocd_ip_allowlist = var.argocd_ip_allowlist
    external_secrets_aws_role = aws_iam_role.external_secrets.arn
  }))
}

resource "aws_autoscaling_group" "microk8s" {
  availability_zones = [var.public_subnet_az]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy = "lowest-price"
    }

    launch_template {
      launch_template_specification {
        launch_template_id      = aws_launch_template.microk8s.id
        version = "$Latest"
      }
    }
  }
}

resource "aws_iam_policy_attachment" "cloudwatch_logging" {
  name       = "cloudwatch_logging"
  roles      = [aws_iam_role.wireguard.name, aws_iam_role.microk8s.name]
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_policy_attachment" "elastic_ip" {
  name       = "elastic_ip"
  roles      = [aws_iam_role.wireguard.name, aws_iam_role.microk8s.name]
  policy_arn = aws_iam_policy.associate_elastic_ip.arn
}

resource "aws_iam_policy_attachment" "microk8s_route_53" {
  name       = "microk8s_route_53"
  roles      = [aws_iam_role.microk8s.name]
  policy_arn = aws_iam_policy.microk8s_route_53.arn
}
