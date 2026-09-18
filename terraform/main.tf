# main.tf
#
# WHAT THIS FILE DOES:
# Declares the actual AWS resources: a security group (firewall rules)
# and an EC2 instance. Running `tofu apply` reads this file, compares it
# to the current real-world state (tracked in terraform.tfstate), and
# makes only the API calls needed to close the gap between "what exists"
# and "what this file says should exist."
#
# WHY THIS MATTERS FOR LEARNING:
# This "declarative + state diffing" model is the core idea behind every
# IaC tool. You never write "create an instance" as an imperative step —
# you write "an instance like this should exist" and let Terraform figure
# out the create/update/destroy calls. Run `tofu apply` again after
# changing var.instance_type, and Terraform will show you a plan to
# *modify* the existing instance rather than create a second one.

# ---------------------------------------------------------------------------
# Data source: look up the latest official Ubuntu 24.04 LTS AMI at apply
# time, instead of hardcoding an AMI ID (AMI IDs are region-specific and
# get replaced periodically — hardcoding one is a common source of IaC
# rot where a config quietly stops working in a new region or months later).
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Security group: this IS the "Network settings" step you did by hand in
# the console earlier, just expressed as code instead of console clicks.
# Same principle as before — SSH scoped to your IP, not 0.0.0.0/0.
# ---------------------------------------------------------------------------
resource "aws_security_group" "cluster_node" {
  name        = "${var.project_name}-sg"
  description = "Security group for the single-node k3s cluster host"

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "App NodePort, from my IP only"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Kubernetes API server (6443), from my IP only - lets kubectl on your Mac talk to the cluster remotely if you choose to"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "Allow all outbound (package installs, pulling images, git, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# ---------------------------------------------------------------------------
# The EC2 instance itself. Note everything here is either a variable or
# derived from a data source — no hardcoded AMI, no hardcoded IP.
# ---------------------------------------------------------------------------
resource "aws_instance" "cluster_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.cluster_node.id]

  root_block_device {
    volume_size = 20    # GB — bumped up from the 8GB default; see README
    volume_type = "gp3"
    encrypted   = true  # free, no perf cost — same reasoning as before
  }

  tags = {
    Name    = "${var.project_name}-node"
    Project = var.project_name
  }
}
