output "wireguard_instance_ami" {
  value = aws_instance.wireguard.ami
}

output "wireguard_instance_arn" {
  value = aws_instance.wireguard.arn
}

output "wireguard_instance_public_ip" {
  value = aws_instance.wireguard.public_ip
}

output "microk8s_instance_ami" {
  value = aws_instance.microk8s.ami
}

output "microk8s_instance_arn" {
  value = aws_instance.microk8s.arn
}
