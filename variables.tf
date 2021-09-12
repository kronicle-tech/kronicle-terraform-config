variable "aws_region" {
  description = "AWS region"
  default = "us-west-1"
}

variable "microk8s_instance_type" {
  description = "Type of EC2 instance to provision"
  default = "t2.micro"
}

variable "microk8s_instance_name" {
  description = "EC2 instance name"
  default = "microk8s"
}

