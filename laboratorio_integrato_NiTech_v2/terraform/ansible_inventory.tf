resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"

  content = <<-EOT
    [waf]
    waf_server ansible_host=${aws_instance.waf.public_ip}

    [siem]
    siem_server ansible_host=${aws_instance.siem.private_ip}

    [target]
    target_server ansible_host=${aws_instance.target.private_ip}

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=${var.private_key_path}
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
}