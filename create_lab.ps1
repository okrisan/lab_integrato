$ProjectRoot = "laboratorio_integrato_NiTech"

# Funzione helper per scrivere file in UTF-8 senza BOM e con fine riga LF (compatibile Linux/WSL)
function Write-LinuxFile {
    param (
        [string]$Path,
        [string]$Content
    )
    $FullPath = Join-Path (Get-Location) $Path
    $Dir = Split-Path $FullPath -Parent
    if (!(Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    $NormalizedContent = $Content -replace "`r`n", "`n"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($FullPath, $NormalizedContent, $Utf8NoBom)
    Write-Host "[OK] Creato: $Path" -ForegroundColor Green
}

Write-Host "Generazione progetto $ProjectRoot in corso..." -ForegroundColor Cyan

# ==========================================
# 1. FILE DI CONFIGURAZIONE GIT & README
# ==========================================

Write-LinuxFile "$ProjectRoot/.gitattributes" @'
* text=auto eol=lf
'@

Write-LinuxFile "$ProjectRoot/.gitignore" @'
# Terraform
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
*.tfvars.json
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraform.lock.hcl

# Chiavi SSH e Credenziali
*.pem
*.ppk
*.key
id_ed25519*
credentials

# OS & IDE
.DS_Store
Thumbs.db
.vscode/
'@

Write-LinuxFile "$ProjectRoot/README.md" @'
# AWS Cloud Security & DevSecOps Lab

Laboratorio integrato su AWS Academy Learner Lab (`us-east-1`) con:
- **Terraform (IaC)**: VPC con Subnet Pubblica/Privata, NAT Gateway, Security Groups dinamici (`phase1` vs `phase2`).
- **Ansible (Config Management)**:
  - **Target**: OWASP Juice Shop su Docker.
  - **WAF**: Nginx + ModSecurity v3 + OWASP CRS v4.
  - **SIEM**: Wazuh Server All-in-One + Wazuh Agent.

## Workflow Rapido (da WSL Debian)
1. `cd terraform && terraform init && terraform apply -var="phase=phase1" -auto-approve`
2. Aggiorna gli IP in `ansible/hosts.ini` e nei playbook.
3. Esegui i playbook in `ansible/` e testa l'attacco SQLi diretto (Fase 1).
4. `cd terraform && terraform apply -var="phase=phase2" -auto-approve`
5. Aggiorna `ansible/hosts.ini` (modalità Bastion), riesegui i playbook e verifica il blocco 403 + alert Wazuh (Fase 2).
6. `terraform destroy -var="phase=phase2" -auto-approve` a fine sessione.
'@

# ==========================================
# 2. FILE TERRAFORM
# ==========================================

Write-LinuxFile "$ProjectRoot/terraform/main.tf" @'
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
'@

Write-LinuxFile "$ProjectRoot/terraform/network.tf" @'
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "DevSecOps-VPC"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "DevSecOps-IGW"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-Subnet"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "DevSecOps-NAT-GW"
  }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Public-RouteTable"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Private-RouteTable"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
'@

Write-LinuxFile "$ProjectRoot/terraform/security_groups.tf" @'
variable "phase" {
  type        = string
  default     = "phase1"
  description = "Impostare 'phase1' per esposizione diretta del Target o 'phase2' per isolamento in subnet privata"
}

resource "aws_security_group" "waf_sg" {
  name        = "waf-security-group"
  description = "Traffico HTTP e SSH per WAF"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH da ovunque"
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

  tags = {
    Name = "WAF-SG"
  }
}

resource "aws_security_group" "siem_sg" {
  name        = "siem-security-group"
  description = "Dashboard Wazuh e comunicazione Agent"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh Dashboard HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh Agent Events"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Wazuh Agent Registration"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SIEM-SG"
  }
}

resource "aws_security_group" "target_sg" {
  name        = "target-security-group"
  description = "Regole dinamiche per Target Juice Shop"
  vpc_id      = aws_vpc.main.id

  # FASE 1: Esposizione diretta
  dynamic "ingress" {
    for_each = var.phase == "phase1" ? [1] : []
    content {
      description = "FASE 1: SSH pubblico diretto"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = var.phase == "phase1" ? [1] : []
    content {
      description = "FASE 1: Esposizione diretta Juice Shop su porta 3000"
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # FASE 2: Isolamento Zero Trust
  dynamic "ingress" {
    for_each = var.phase == "phase2" ? [1] : []
    content {
      description = "FASE 2: SSH solo da Subnet Pubblica (Bastion WAF)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.1.0/24"]
    }
  }

  dynamic "ingress" {
    for_each = var.phase == "phase2" ? [1] : []
    content {
      description     = "FASE 2: Porta 3000 accessibile SOLO dal SG del WAF"
      from_port       = 3000
      to_port         = 3000
      protocol        = "tcp"
      security_groups = [aws_security_group.waf_sg.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Target-SG"
  }
}
'@

Write-LinuxFile "$ProjectRoot/terraform/instances.tf" @'
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
'@

# ==========================================
# 3. FILE ANSIBLE
# ==========================================

Write-LinuxFile "$ProjectRoot/ansible/hosts.ini" @'
[waf]
waf_node ansible_host=<WAF_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/labsuser.pem

[siem]
siem_node ansible_host=<SIEM_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/labsuser.pem

[target]
# IN FASE 1: inserisci <TARGET_PUBLIC_IP>
# IN FASE 2: inserisci <TARGET_PRIVATE_IP> e decommenta il blocco [target:vars] sotto
target_node ansible_host=<TARGET_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/labsuser.pem

# [target:vars]
# ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ubuntu@<WAF_PUBLIC_IP> -i ~/.ssh/labsuser.pem"'

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
'@

Write-LinuxFile "$ProjectRoot/ansible/playbook1_target.yml" @'
---
- name: Deploy OWASP Juice Shop su Target
  hosts: target
  become: yes
  tasks:
    - name: Aggiorna cache apt e installa dipendenze
      apt:
        name:
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
          - python3-docker
        state: present
        update_cache: yes

    - name: Crea directory per keyring Docker
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Scarica chiave GPG di Docker
      get_url:
        url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.asc
        mode: '0644'

    - name: Aggiungi repository Docker
      apt_repository:
        repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
        state: present

    - name: Installa Docker Engine
      apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
        state: present
        update_cache: yes

    - name: Avvia e abilita servizio Docker
      systemd:
        name: docker
        state: started
        enabled: yes

    - name: Avvia container OWASP Juice Shop
      community.docker.docker_container:
        name: juiceshop
        image: bkimminich/juice-shop:v15.0.0
        state: started
        restart_policy: always
        published_ports:
          - "3000:3000"
'@

Write-LinuxFile "$ProjectRoot/ansible/playbook2_waf.yml" @'
---
- name: Configurazione WAF Nginx con ModSecurity v3 e OWASP CRS
  hosts: waf
  become: yes
  vars:
    target_private_ip: "<TARGET_PRIVATE_IP>"
  tasks:
    - name: Installa Nginx, modulo ModSecurity v3 e Git
      apt:
        name:
          - nginx
          - libnginx-mod-http-modsecurity
          - git
        state: present
        update_cache: yes

    - name: Crea directory /etc/modsecurity
      file:
        path: /etc/modsecurity
        state: directory
        mode: '0755'

    - name: Scarica configurazione consigliata ModSecurity
      get_url:
        url: https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3/master/modsecurity.conf-recommended
        dest: /etc/modsecurity/modsecurity.conf
        mode: '0644'

    - name: Scarica unicode.mapping per ModSecurity
      get_url:
        url: https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3/master/unicode.mapping
        dest: /etc/modsecurity/unicode.mapping
        mode: '0644'

    - name: Imposta SecRuleEngine su On (Blocking Mode)
      lineinfile:
        path: /etc/modsecurity/modsecurity.conf
        regexp: '^SecRuleEngine'
        line: 'SecRuleEngine On'

    - name: Clona OWASP ModSecurity Core Rule Set (CRS v4)
      git:
        repo: 'https://github.com/coreruleset/coreruleset.git'
        dest: /etc/modsecurity/crs
        version: v4.0/main
        force: yes

    - name: Configura crs-setup.conf
      copy:
        src: /etc/modsecurity/crs/crs-setup.conf.example
        dest: /etc/modsecurity/crs/crs-setup.conf
        remote_src: yes
        force: no

    - name: Includi OWASP CRS in ModSecurity
      blockinfile:
        path: /etc/modsecurity/modsecurity.conf
        block: |
          Include /etc/modsecurity/crs/crs-setup.conf
          Include /etc/modsecurity/crs/rules/*.conf

    - name: Configura Nginx come Reverse Proxy protetto da WAF
      copy:
        dest: /etc/nginx/sites-available/default
        content: |
          server {
              listen 80 default_server;
              listen [::]:80 default_server;

              server_name _;

              modsecurity on;
              modsecurity_rules_file /etc/modsecurity/modsecurity.conf;

              location / {
                  proxy_pass http://{{ target_private_ip }}:3000;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              }
          }

    - name: Riavvia Nginx
      systemd:
        name: nginx
        state: restarted
        enabled: yes
'@

Write-LinuxFile "$ProjectRoot/ansible/playbook3_wazuh.yml" @'
---
- name: Deploy Wazuh SIEM Server (All-in-One)
  hosts: siem
  become: yes
  tasks:
    - name: Scarica ed esegui Wazuh Installation Assistant
      shell: |
        curl -sO https://packages.wazuh.com/4.7/wazuh-install.sh
        bash ./wazuh-install.sh -a -i > /root/wazuh-passwords.txt
      args:
        creates: /root/wazuh-passwords.txt

    - name: Estrai password admin di Wazuh Dashboard
      shell: grep "User: admin" -A 1 /root/wazuh-passwords.txt | tail -n 1 | awk '{print $2}'
      register: wazuh_password

    - name: Mostra credenziali di accesso Wazuh
      debug:
        msg: "Wazuh Dashboard URL: https://{{ ansible_host }} | User: admin | Password: {{ wazuh_password.stdout }}"

- name: Deploy e Connessione Agent su WAF e Target
  hosts: waf, target
  become: yes
  vars:
    siem_private_ip: "<SIEM_PRIVATE_IP>"
  tasks:
    - name: Aggiungi chiave GPG Wazuh
      apt_key:
        url: https://packages.wazuh.com/key/GPG-KEY-WAZUH
        state: present

    - name: Aggiungi repository Wazuh
      apt_repository:
        repo: "deb https://packages.wazuh.com/4.x/apt/ stable main"
        state: present

    - name: Installa Wazuh Agent
      apt:
        name: wazuh-agent
        state: present
        update_cache: yes

    - name: Configura IP del Wazuh Manager nel file ossec.conf
      replace:
        path: /var/ossec/etc/ossec.conf
        regexp: '<address>127.0.0.1</address>'
        replace: '<address>{{ siem_private_ip }}</address>'

    - name: Aggiungi monitoraggio log ModSecurity (Solo su WAF)
      blockinfile:
        path: /var/ossec/etc/ossec.conf
        insertbefore: '</ossec_config>'
        block: |
          <localfile>
            <log_format>syslog</log_format>
            <location>/var/log/modsec_audit.log</location>
          </localfile>
      when: "'waf' in group_names"

    - name: Abilita ed avvia Wazuh Agent
      systemd:
        name: wazuh-agent
        state: restarted
        enabled: yes
'@

Write-Host "`nStruttura creata con successo in ./$ProjectRoot!" -ForegroundColor Yellow