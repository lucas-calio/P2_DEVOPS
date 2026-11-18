###############################################################################
# Avaliação Prática de DevOps - Prova C - Cadastro de Cursos
# OpenTofu: provisiona duas VMs (EC2) na AWS
#   VM1 -> servidor web + aplicação HTML (Docker)
#   VM2 -> API Node.js + MySQL (Docker Compose)
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variáveis
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo das instâncias EC2"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Nome do key pair JÁ EXISTENTE na AWS (no AWS Academy normalmente é 'vockey')"
  type        = string
  default     = "vockey"
}

variable "ssh_private_key_path" {
  description = "Caminho da chave privada (.pem) usada pelo Ansible para acessar as VMs"
  type        = string
  default     = "~/.ssh/labsuser.pem"
}

# ---------------------------------------------------------------------------
# Imagem: Ubuntu 22.04 LTS oficial (Canonical)
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720108685"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "vm1_web" {
  name_prefix = "avaliacao-vm1-web-"
  description = "VM1 - SSH e HTTP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP - aplicacao web"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "avaliacao-vm1-web" }
}

resource "aws_security_group" "vm2_api" {
  name_prefix = "avaliacao-vm2-api-"
  description = "VM2 - SSH e API REST (MySQL fica apenas na rede interna do Docker)"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "API REST Node.js"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "avaliacao-vm2-api" }
}

# ---------------------------------------------------------------------------
# VM1 - Aplicação web
# ---------------------------------------------------------------------------
resource "aws_instance" "vm1" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.vm1_web.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/cloud_init.yaml")

  root_block_device {
    volume_size = 10
  }

  tags = { Name = "VM1-aplicacao-web" }
}

# ---------------------------------------------------------------------------
# VM2 - API + banco
# ---------------------------------------------------------------------------
resource "aws_instance" "vm2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.vm2_api.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/cloud_init.yaml")

  root_block_device {
    volume_size = 10
  }

  tags = { Name = "VM2-api-banco" }
}

# ---------------------------------------------------------------------------
# Gera automaticamente o inventário do Ansible com os IPs das VMs
# ---------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory"
  file_permission = "0644"
  content         = <<-EOT
    # Gerado automaticamente pelo OpenTofu (iac/main.tf)
    [web]
    vm1 ansible_host=${aws_instance.vm1.public_ip}

    [api]
    vm2 ansible_host=${aws_instance.vm2.public_ip}

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${var.ssh_private_key_path}
    ansible_python_interpreter=/usr/bin/python3
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
  EOT
}

# ---------------------------------------------------------------------------
# Saídas
# ---------------------------------------------------------------------------
output "vm1_ip_publico" {
  value = aws_instance.vm1.public_ip
}

output "vm2_ip_publico" {
  value = aws_instance.vm2.public_ip
}

output "url_aplicacao" {
  value = "http://${aws_instance.vm1.public_ip}"
}

output "url_api" {
  value = "http://${aws_instance.vm2.public_ip}:3000/cursos"
}
