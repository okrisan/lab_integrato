resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"

  content = <<-EOT
    [waf]
    waf_server ansible_host=${module.ec2.waf_public_ip}

    [siem]
    siem_server ansible_host=${module.ec2.siem_private_ip}

    [target]
    target_server ansible_host=${module.ec2.target_private_ip}

    [siem:vars]
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p -q ubuntu@${module.ec2.waf_public_ip} -i ${var.private_key_path}"'

    [target:vars]
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p -q ubuntu@${module.ec2.waf_public_ip} -i ${var.private_key_path}"'

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${var.private_key_path}
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    target_private_ip=${module.ec2.target_private_ip}
    siem_private_ip=${module.ec2.siem_private_ip}
  EOT
}