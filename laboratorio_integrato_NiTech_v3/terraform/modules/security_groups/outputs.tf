output "waf_sg_id" { value = aws_security_group.waf_sg.id }
output "target_sg_id" { value = aws_security_group.target_sg.id }
output "siem_sg_id" { value = aws_security_group.siem_sg.id }