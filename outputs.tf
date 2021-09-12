output "microk8s_instance_ami" {
  value = aws_instance.ubuntu.ami
}

output "microk8s_instance_arn" {
  value = aws_instance.ubuntu.arn
}
