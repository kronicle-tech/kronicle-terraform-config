# Terraform Cloud Config

[Terraform Cloud](https://www.terraform.io/cloud) config for the Kronicle live demo

## Testing microk8s Install

The `user-data` script used to install microk8s can be executed and manually tested locally using
`multipass` from Canonical.  

Installing multipass:

1. Download and install VirtualBox: https://www.virtualbox.org/wiki/Downloads
2. Download multipass: https://multipass.run 
3. Configure multipass to use VirtualBox: $ sudo multipass set local.driver=virtualbox

Use multipass to launch a Ubuntu VM and execute the `user-data` script on that VM: 

```shell
$ multipass launch --name microk8s -m 4G
$ multipass exec microk8s bash
ubuntu@microk8s:~$ sudo bash
root@microk8s:/home/ubuntu# vim user-data # Copy and paste the user-data script into vim
root@microk8s:/home/ubuntu# chmod +x user-data 
root@microk8s:/home/ubuntu# ./user-data
root@microk8s:/home/ubuntu# exit
ubuntu@microk8s:~$ exit
$ multipass delete microk8s
$ multipass purge
```
