terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # local - local file만드는데 필요
    local = {
      source    = "hashicorp/local"
      version   = "2.5.3"
    }

    # tls - ssh key 만드는데 필요
    tls = {
      source    = "hashicorp/tls"
      version   = "4.1.0"
    }
  }
}

variable "aws_access_key" {
  description   = "aws access key"
  type          = string
  nullable      = false
  sensitive     = true
  ephemeral     = true
}

variable "aws_secret_key" {
  description   = "aws secret key"
  type          = string
  nullable      = false
  sensitive     = true
  ephemeral     = true
}

variable "vm" {
  description   = "The number of ec2 to create"
  type          = number
  default       = 3
}

resource "tls_private_key" "aws_ssh_key" {
  algorithm   = "RSA"
  rsa_bits    = 4096
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.aws_ssh_key.private_key_pem
  filename        = pathexpand("~/.ssh/aws_ssh_key")
  file_permission = "0400"
}

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.aws_ssh_key.public_key_openssh
  filename        = pathexpand("~/.ssh/aws_ssh_key.pub")
  file_permission = "0644"
}

# aws configure
provider "aws" {
  region      = "ap-northeast-2"
  access_key  = var.aws_access_key
  secret_key  = var.aws_secret_key
}

resource "aws_key_pair" "main" {
  key_name   = "tf-key"
  public_key = tls_private_key.aws_ssh_key.public_key_openssh
}

resource "aws_vpc" "main" {
  cidr_block = "192.168.0.0/16"
  tags = {
    Name = "tf-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "tf-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  tags = {
    Name = "tf-igw"
  }
}

data "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_internet_gateway_attachment" "main" {
  internet_gateway_id = aws_internet_gateway.main.id
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "route_ig" {
  route_table_id = data.aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.main.id
}

resource "aws_security_group" "main" {
  name = "tf-sg"
  vpc_id = aws_vpc.main.id
  description = "for tf"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow all traffic from within the VPC"
    from_port   = 0 # 모든 포트
    to_port     = 0 # 모든 포트
    protocol    = "-1" # 모든 프로토콜
    self = true
  }

  # 아웃바운드 규칙 (Egress)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "node" {
  name = "TFNodeRole"
  assume_role_policy = jsonencode({
    Version: "2012-10-17",
    Statement: [
        {
            Effect: "Allow",
            Principal: {
                Service: "ec2.amazonaws.com"
            },
            Action: "sts:AssumeRole"
        }]
  })
}

resource "aws_iam_policy" "node" {
  name = "TFNodePolicy"
  policy = jsonencode({
      Version: "2012-10-17",
      Statement: [{
        Effect: "Allow",
        Action: [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeVpcs",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:BatchGetImage",
          "elasticloadbalancing:*",
          "iam:CreateServiceLinkedRole",
          "kms:DescribeKey"],
        Resource: "*"}]
    })
}

resource "aws_iam_role_policy_attachment" "node" {
  role = aws_iam_role.node.name
  policy_arn = aws_iam_policy.node.arn
}

resource "aws_iam_instance_profile" "node" {
  name = "TFNodeProfile"
  role = aws_iam_role.node.name
}

resource "aws_instance" "master" {
  ami = "ami-00e73adb2e2c80366"
  instance_type = "t3.large"
  key_name = aws_key_pair.main.key_name
  security_groups = [aws_security_group.main.id]
  subnet_id = aws_subnet.public.id
  iam_instance_profile = aws_iam_instance_profile.node.name
  tags = {
    Name = "master"
  }
}

resource "aws_instance" "worker" {
  count = var.vm - 1

  ami = "ami-00e73adb2e2c80366"
  instance_type = "t3.small"
  iam_instance_profile = aws_iam_instance_profile.node.name

  key_name = aws_key_pair.main.key_name
  security_groups = [aws_security_group.main.id]
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "worker${count.index + 1}"
  }
}

resource "local_file" "inventory" {
  filename        = "${path.module}/../inventory.ini"
  file_permission = "0666"
  content         = <<EOF
[masters]
master-node ansible_host=${aws_instance.master.public_ip}

[workers]
${join("\n",  [for i, worker in aws_instance.worker: "worker-node${i+1} ansible_host=${worker.public_ip}"])}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${pathexpand("~/.ssh/aws_ssh_key")}
EOF
}
