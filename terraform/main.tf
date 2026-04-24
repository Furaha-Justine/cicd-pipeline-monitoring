terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Latest Amazon Linux 2023 AMI ───────────────────────────────────────────────
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── TLS key pair ───────────────────────────────────────────────────────────────
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/ec2_key.pem"
  file_permission = "0600"
}

# ── IAM role for Jenkins EC2 ───────────────────────────────────────────────────
resource "aws_iam_role" "jenkins_role" {
  name = "${var.project_name}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-jenkins-role" }
}

resource "aws_iam_role_policy" "jenkins_ec2_policy" {
  name = "${var.project_name}-jenkins-ec2-policy"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}

# ── IAM role for App EC2 (CloudWatch logs for Docker awslogs driver) ─────────
resource "aws_iam_role" "app_role" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-app-role" }
}

resource "aws_iam_role_policy" "app_cloudwatch_logs_policy" {
  name = "${var.project_name}-app-cloudwatch-logs-policy"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.project_name}-app-profile"
  role = aws_iam_role.app_role.name
}

# ── Security group: Jenkins ────────────────────────────────────────────────────
resource "aws_security_group" "jenkins_sg" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Jenkins server - SSH + UI"
  tags        = { Name = "${var.project_name}-jenkins-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_ssh" {
  security_group_id = aws_security_group.jenkins_sg.id
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_ui" {
  security_group_id = aws_security_group.jenkins_sg.id
  description       = "Jenkins UI"
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "jenkins_outbound" {
  security_group_id = aws_security_group.jenkins_sg.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Security group: App ────────────────────────────────────────────────────────
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "App server - SSH + app port"
  tags        = { Name = "${var.project_name}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app_sg.id
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_port" {
  security_group_id = aws_security_group.app_sg.id
  description       = "App port"
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_node_exporter_from_monitoring" {
  security_group_id            = aws_security_group.app_sg.id
  description                  = "Node Exporter from monitoring EC2"
  from_port                    = 9100
  to_port                      = 9100
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_vpc_security_group_egress_rule" "app_outbound" {
  security_group_id = aws_security_group.app_sg.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Security group: Monitoring (Prometheus + Grafana) ────────────────────────
resource "aws_security_group" "monitoring_sg" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Monitoring server - SSH + Prometheus + Grafana"
  tags        = { Name = "${var.project_name}-monitoring-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_ssh" {
  security_group_id = aws_security_group.monitoring_sg.id
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_cidr
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_prometheus" {
  security_group_id = aws_security_group.monitoring_sg.id
  description       = "Prometheus UI"
  from_port         = 9090
  to_port           = 9090
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_cidr
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_grafana" {
  security_group_id = aws_security_group.monitoring_sg.id
  description       = "Grafana UI"
  from_port         = 3001
  to_port           = 3001
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_cidr
}

resource "aws_vpc_security_group_egress_rule" "monitoring_outbound" {
  security_group_id = aws_security_group.monitoring_sg.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Jenkins EC2 ────────────────────────────────────────────────────────────────
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.jenkins_instance_type
  key_name               = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "${var.project_name}-jenkins" }
}

# ── App EC2 ────────────────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.app_instance_type
  key_name               = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.app_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "${var.project_name}-app" }
}

# ── Monitoring EC2 ────────────────────────────────────────────────────────────
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.monitoring_instance_type
  key_name               = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "${var.project_name}-monitoring" }
}

# ── Ansible inventory ──────────────────────────────────────────────────────────
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    jenkins_ip    = aws_instance.jenkins.public_ip
    app_ip        = aws_instance.app.public_ip
    monitoring_ip = aws_instance.monitoring.public_ip
    key_path      = abspath("${path.module}/ec2_key.pem")
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
