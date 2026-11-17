resource "aws_security_group" "waf_sg" {
  name        = "waf-security-group"
  description = "Traffico HTTP e SSH per Bastion WAF"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH pubblico"
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

  tags = { Name = "WAF-SG" }
}