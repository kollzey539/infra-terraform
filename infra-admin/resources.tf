# Generate new SSH key pair for bastion host
resource "tls_private_key" "bastion_rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key-${formatdate("YYYYMMDD", timestamp())}"
  public_key = tls_private_key.bastion_rsa.public_key_openssh
}

# Reference existing VPC
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["main-vpc"]
  }
}

# Reference existing public subnet
data "aws_subnet" "public" {
  filter {
    name   = "tag:Name"
    values = ["nat-gateway-subnet"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# Security group with open inbound SSH (default egress)
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-security-group"
  description = "Allow SSH from anywhere"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}


# Bastion host
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = aws_key_pair.bastion_key.key_name

  tags = {
    Name = "bastion-host"
  }
}

# Latest Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ECR repository
resource "aws_ecr_repository" "rigetti_demo" {
  name                 = "rigettidemo"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.rigetti_demo.repository_url
}

output "ssh_private_key" {
  value     = tls_private_key.bastion_rsa.private_key_pem
  sensitive = true
}