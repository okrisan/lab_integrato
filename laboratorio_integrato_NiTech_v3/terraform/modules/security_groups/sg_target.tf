resource "aws_security_group" "target_sg" {
  name        = "target-security-group"
  description = "Accesso Zero-Trust a Juice Shop in Subnet Privata"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH solo da Subnet Pubblica (Bastion WAF)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    description     = "Porta 3000 accessibile SOLO dal SG del WAF"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.waf_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Target-SG" }
}