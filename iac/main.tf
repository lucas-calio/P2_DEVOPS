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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
  default     = "us-east-2"
}

variable "instance_type" {
  description = "Tipo das instâncias EC2"
  type        = string
  default     = "t3.micro"
}

# ---------------------------------------------------------------------------
# Chave SSH gerada pelo próprio OpenTofu (não precisa copiar nenhum .pem).
# A chave privada é gravada em ansible/avaliacao_key.pem (ignorada pelo git).
# ---------------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "avaliacao" {
  key_name_prefix = "avaliacao-cursos-"
  public_key      = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  filename        = "${path.module}/../ansible/avaliacao_key.pem"
  content         = tls_private_key.ssh.private_key_pem
  file_permission = "0400"
}

# ---------------------------------------------------------------------------
# Imagem: Ubuntu 22.04 LTS oficial (Canonical)
# ---------------------------------------------------------------------------
# Parâmetro público mantido pela Canonical no SSM: sempre aponta para a AMI
# estável mais recente do Ubuntu 22.04 na região.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
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
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.avaliacao.key_name
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
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.avaliacao.key_name
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
    ansible_ssh_private_key_file=${abspath(local_sensitive_file.ssh_private_key.filename)}
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
