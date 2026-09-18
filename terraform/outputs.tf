# outputs.tf
#
# WHAT THIS FILE DOES:
# Surfaces values from the created resources back to you after `tofu
# apply` finishes — so you don't have to go dig them out of the AWS
# console. `tofu output` (any time later) reprints these.
#
# WHY THIS MATTERS FOR LEARNING:
# Outputs are also how Terraform configs pass data between each other
# (a "root module" output can feed a child module's input) and how
# other tools in this project consume Terraform's results — the Ansible
# step needs this instance's public IP to know where to SSH, and rather
# than you copy-pasting it by hand, our Makefile/README command generates
# an Ansible inventory file directly from `tofu output`.

output "public_ip" {
  description = "Public IPv4 address of the cluster node. Feed this to Ansible as the SSH target."
  value       = aws_instance.cluster_node.public_ip
}

output "instance_id" {
  description = "EC2 instance ID, useful for console lookups or `aws ec2` CLI commands."
  value       = aws_instance.cluster_node.id
}

output "ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.cluster_node.public_ip}"
}
