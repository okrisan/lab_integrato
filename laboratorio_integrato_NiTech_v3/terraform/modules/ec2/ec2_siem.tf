resource "aws_instance" "siem" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.siem_sg_id]
  key_name               = var.key_name
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "SIEM-Wazuh" }
}