resource "aws_instance" "waf" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.waf_sg.id]
  key_name               = "vockey"
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 15
    volume_type = "gp2"
  }

  tags = {
    Name = "WAF-ModSecurity"
  }
}

resource "aws_instance" "siem" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.siem_sg.id]
  key_name               = "vockey"
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }

  tags = {
    Name = "SIEM-Wazuh"
  }
}

resource "aws_instance" "target" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = var.phase == "phase1" ? aws_subnet.public.id : aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.target_sg.id]
  key_name               = "vockey"
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 15
    volume_type = "gp2"
  }

  tags = {
    Name = "Target-JuiceShop"
  }
}

output "waf_public_ip" {
  value       = aws_instance.waf.public_ip
  description = "IP Pubblico WAF"
}

output "siem_public_ip" {
  value       = aws_instance.siem.public_ip
  description = "IP Pubblico SIEM Wazuh"
}

output "siem_private_ip" {
  value       = aws_instance.siem.private_ip
  description = "IP Privato SIEM Wazuh (per configurazione Agent)"
}

output "target_public_ip" {
  value       = var.phase == "phase1" ? aws_instance.target.public_ip : "N/A (In Subnet Privata)"
  description = "IP Pubblico Target (Attivo solo in Fase 1)"
}

output "target_private_ip" {
  value       = aws_instance.target.private_ip
  description = "IP Privato Target"
}