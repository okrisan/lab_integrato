output "waf_public_ip" {
  description = "IP Pubblico WAF"
  value       = module.ec2.waf_public_ip
}

output "target_private_ip" {
  description = "IP Privato Target"
  value       = module.ec2.target_private_ip
}

output "siem_private_ip" {
  description = "IP Privato SIEM"
  value       = module.ec2.siem_private_ip
}