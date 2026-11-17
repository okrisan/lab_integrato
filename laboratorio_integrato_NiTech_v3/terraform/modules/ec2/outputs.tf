output "waf_public_ip" { value = aws_instance.waf.public_ip }
output "target_private_ip" { value = aws_instance.target.private_ip }
output "siem_private_ip" { value = aws_instance.siem.private_ip }