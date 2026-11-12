variable "phase" {
  type        = string
  default     = "phase1"
  description = "Impostare 'phase1' per esposizione diretta del Target o 'phase2' per isolamento in subnet privata"
}

resource "aws_security_group" "waf_sg" {
  name        = "waf-security-group"
  description = "Traffico HTTP e SSH per WAF"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH da ovunque"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP pubblico"
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

  tags = {
    Name = "WAF-SG"
  }
}

resource "aws_security_group" "siem_sg" {
  name        = "siem-security-group"
  description = "Dashboard Wazuh e comunicazione Agent"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh Dashboard HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh Agent Events"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Wazuh Agent Registration"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SIEM-SG"
  }
}

resource "aws_security_group" "target_sg" {
  name        = "target-security-group"
  description = "Regole dinamiche per Target Juice Shop"
  vpc_id      = aws_vpc.main.id

  # FASE 1: Esposizione diretta
  dynamic "ingress" {
    for_each = var.phase == "phase1" ? [1] : []
    content {
      description = "FASE 1: SSH pubblico diretto"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = var.phase == "phase1" ? [1] : []
    content {
      description = "FASE 1: Esposizione diretta Juice Shop su porta 3000"
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # FASE 2: Isolamento Zero Trust
  dynamic "ingress" {
    for_each = var.phase == "phase2" ? [1] : []
    content {
      description = "FASE 2: SSH solo da Subnet Pubblica (Bastion WAF)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.1.0/24"]
    }
  }

  dynamic "ingress" {
    for_each = var.phase == "phase2" ? [1] : []
    content {
      description     = "FASE 2: Porta 3000 accessibile SOLO dal SG del WAF"
      from_port       = 3000
      to_port         = 3000
      protocol        = "tcp"
      security_groups = [aws_security_group.waf_sg.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Target-SG"
  }
}