resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"

  content = <<-EOT
    [waf]
    waf_server ansible_host=${aws_instance.waf.public_ip}

    [siem]
    siem_server ansible_host=${aws_instance.siem.public_ip}

    [target]
    target_server ansible_host=${aws_instance.target.private_ip}

    [target:vars]
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ubuntu@${aws_instance.waf.public_ip} -i ${var.private_key_path}"'

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${var.private_key_path}
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    target_private_ip=${aws_instance.target.private_ip}
    siem_private_ip=${aws_instance.siem.private_ip}
  EOT
}