resource "aws_instance" "waf" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.waf_sg_id]
  key_name               = var.key_name
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
  }

  tags = { Name = "WAF-ModSecurity" }
}