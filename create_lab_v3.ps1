# Script per la generazione automatica della struttura di progetto DevSecOps Zero-Trust

$rootFolder = "laboratorio_integrato_NiTech_v3"
Write-Host "Creazione struttura in corso su: $rootFolder" -ForegroundColor Cyan

# 1. Definizione e creazione delle directory
$directories = @(
    "$rootFolder\.github\workflows",
    "$rootFolder\terraform\modules\vpc",
    "$rootFolder\terraform\modules\security_groups",
    "$rootFolder\terraform\modules\ec2",
    "$rootFolder\ansible"
)

foreach ($dir in $directories) {
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Helper per la creazione dei file con contenuto UTF-8 (senza BOM)
function Write-ProjectFile {
    param (
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText((Join-Path -Path $PSScriptRoot -ChildPath $Path), $Content.TrimStart(), [System.Text.Encoding]::UTF8)
    Write-Host " [OK] Creato: $Path" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# TERRAFORM - MODULE VPC
# -----------------------------------------------------------------------------

Write-ProjectFile -Path "$rootFolder\terraform\modules\vpc\vpc.tf" -Content @'
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.environment}-VPC" }
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\vpc\subnets.tf" -Content @'
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.environment}-Public-Subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.az

  tags = { Name = "${var.environment}-Private-Subnet" }
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\vpc\gateways.tf" -Content @'
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-IGW" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${var.environment}-NAT-GW" }

  depends_on = [aws_internet_gateway.gw]
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\vpc\route_tables.tf" -Content @'
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "${var.environment}-Public-RT" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.environment}-Private-RT" }
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

Write-ProjectFile -Path "$rootFolder\terraform\modules\vpc\variables.tf" -Content @'
variable "vpc_cidr" { type = string }
variable "public_subnet_cidr" { type = string }
variable "private_subnet_cidr" { type = string }
variable "az" { type = string }
variable "environment" { type = string }
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\vpc\outputs.tf" -Content @'
output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_id" { value = aws_subnet.public.id }
output "private_subnet_id" { value = aws_subnet.private.id }
'@

# -----------------------------------------------------------------------------
# TERRAFORM - MODULE SECURITY GROUPS
# -----------------------------------------------------------------------------

Write-ProjectFile -Path "$rootFolder\terraform\modules\security_groups\sg_waf.tf" -Content @'
resource "aws_security_group" "waf_sg" {
  name        = "waf-security-group"
  description = "Traffico HTTP e SSH per Bastion WAF"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH pubblico"
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

  tags = { Name = "WAF-SG" }
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\security_groups\sg_target.tf" -Content @'
resource "aws_security_group" "target_sg" {
  name        = "target-security-group"
  description = "Accesso Zero-Trust a Juice Shop in Subnet Privata"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH solo da Subnet Pubblica (Bastion WAF)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    description     = "Porta 3000 accessibile SOLO dal SG del WAF"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.waf_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Target-SG" }
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\security_groups\sg_siem.tf" -Content @'
resource "aws_security_group" "siem_sg" {
  name        = "siem-security-group"
  description = "Dashboard e comunicazioni Agent Wazuh"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH solo da Subnet Pubblica (Bastion WAF)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
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

  tags = { Name = "SIEM-SG" }
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\security_groups\variables.tf" -Content @'
variable "vpc_id" { type = string }
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\security_groups\outputs.tf" -Content @'
output "waf_sg_id" { value = aws_security_group.waf_sg.id }
output "target_sg_id" { value = aws_security_group.target_sg.id }
output "siem_sg_id" { value = aws_security_group.siem_sg.id }
'@

# -----------------------------------------------------------------------------
# TERRAFORM - MODULE EC2
# -----------------------------------------------------------------------------

Write-ProjectFile -Path "$rootFolder\terraform\modules\ec2\ami.tf" -Content @'
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

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

Write-ProjectFile -Path "$rootFolder\terraform\modules\ec2\ec2_waf.tf" -Content @'
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
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\ec2\ec2_target.tf" -Content @'
resource "aws_instance" "target" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.target_sg_id]
  key_name               = var.key_name
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
  }

  tags = { Name = "Target-JuiceShop" }
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\ec2\ec2_siem.tf" -Content @'
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
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\ec2\variables.tf" -Content @'
variable "public_subnet_id" { type = string }
variable "private_subnet_id" { type = string }
variable "waf_sg_id" { type = string }
variable "target_sg_id" { type = string }
variable "siem_sg_id" { type = string }
variable "key_name" { type = string }
'@

Write-ProjectFile -Path "$rootFolder\terraform\modules\ec2\outputs.tf" -Content @'
output "waf_public_ip" { value = aws_instance.waf.public_ip }
output "target_private_ip" { value = aws_instance.target.private_ip }
output "siem_private_ip" { value = aws_instance.siem.private_ip }
'@

# -----------------------------------------------------------------------------
# TERRAFORM - ROOT CONFIGURATION
# -----------------------------------------------------------------------------

Write-ProjectFile -Path "$rootFolder\terraform\providers.tf" -Content @'
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\variables.tf" -Content @'
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ssh_key_name" {
  type    = string
  default = "vockey"
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/labsuser.pem"
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\main.tf" -Content @'
module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  az                  = "us-east-1a"
  environment         = "devsecops-lab"
}

module "security_groups" {
  source = "./modules/security_groups"
  vpc_id = module.vpc.vpc_id
}

module "ec2" {
  source            = "./modules/ec2"
  public_subnet_id  = module.vpc.public_subnet_id
  private_subnet_id = module.vpc.private_subnet_id
  waf_sg_id         = module.security_groups.waf_sg_id
  target_sg_id      = module.security_groups.target_sg_id
  siem_sg_id        = module.security_groups.siem_sg_id
  key_name          = var.ssh_key_name
}
'@

Write-ProjectFile -Path "$rootFolder\terraform\outputs.tf" -Content @'
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
'@

Write-ProjectFile -Path "$rootFolder\terraform\ansible_inventory.tf" -Content @'
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
'@

# -----------------------------------------------------------------------------
# ANSIBLE PLAYBOOKS
# -----------------------------------------------------------------------------

Write-ProjectFile -Path "$rootFolder\ansible\playbook1_target.yml" -Content @'
---
- name: Deploy OWASP Juice Shop su Target (Subnet Privata)
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

Write-ProjectFile -Path "$rootFolder\ansible\playbook2_waf.yml" -Content @'
---
- name: Configurazione WAF Nginx con ModSecurity v3 e OWASP CRS (Default Off per Fase 1)
  hosts: waf
  become: yes
  tasks:
    - name: Abilita repository universe
      apt_repository:
        repo: "deb http://archive.ubuntu.com/ubuntu {{ ansible_distribution_release }} universe"
        state: present

    - name: Installa Nginx, libmodsecurity e dipendenze di compilazione
      apt:
        name:
          - nginx
          - libmodsecurity3
          - libmodsecurity-dev
          - git
          - build-essential
          - libpcre3-dev
          - zlib1g-dev
          - libssl-dev
          - curl
        state: present
        update_cache: yes

    - name: Compila il modulo dinamico ModSecurity-nginx
      shell: |
        NGINX_VER=$(nginx -v 2>&1 | grep -oP '(?<=nginx/)[0-9.]+')
        cd /tmp
        curl -sL "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz" | tar xz
        rm -rf /tmp/ModSecurity-nginx
        git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git /tmp/ModSecurity-nginx
        cd "/tmp/nginx-${NGINX_VER}"
        ./configure --with-compat --add-dynamic-module=/tmp/ModSecurity-nginx
        make modules
        cp objs/ngx_http_modsecurity_module.so /usr/lib/nginx/modules/
      args:
        creates: /usr/lib/nginx/modules/ngx_http_modsecurity_module.so

    - name: Abilita il modulo ModSecurity in Nginx
      copy:
        dest: /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf
        content: |
          load_module /usr/lib/nginx/modules/ngx_http_modsecurity_module.so;
        mode: '0644'

    - name: Crea directory /etc/modsecurity
      file:
        path: /etc/modsecurity
        state: directory
        mode: '0755'

    - name: Scarica configurazione consigliata ModSecurity (v3.0.6)
      get_url:
        url: https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3.0.6/modsecurity.conf-recommended
        dest: /etc/modsecurity/modsecurity.conf
        force: yes
        mode: '0644'

    - name: Scarica unicode.mapping per ModSecurity (v3.0.6)
      get_url:
        url: https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3.0.6/unicode.mapping
        dest: /etc/modsecurity/unicode.mapping
        force: yes
        mode: '0644'

    - name: Pre-crea file di audit log ModSecurity con permessi per Nginx
      file:
        path: /var/log/modsec_audit.log
        state: touch
        owner: www-data
        group: adm
        mode: '0640'

    - name: Imposta SecRuleEngine su Off (FASE 1 - Pass-Through)
      lineinfile:
        path: /etc/modsecurity/modsecurity.conf
        regexp: '^SecRuleEngine'
        line: 'SecRuleEngine Off'

    - name: Clona OWASP ModSecurity Core Rule Set (v3.3.2)
      git:
        repo: 'https://github.com/coreruleset/coreruleset.git'
        dest: /etc/modsecurity/crs
        version: v3.3.2
        force: yes

    - name: Configura crs-setup.conf
      copy:
        src: /etc/modsecurity/crs/crs-setup.conf.example
        dest: /etc/modsecurity/crs/crs-setup.conf
        remote_src: yes
        force: yes

    - name: Includi OWASP CRS in ModSecurity
      blockinfile:
        path: /etc/modsecurity/modsecurity.conf
        block: |
          Include /etc/modsecurity/crs/crs-setup.conf
          Include /etc/modsecurity/crs/rules/*.conf

    - name: Configura Nginx come Reverse Proxy
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

    - name: Verifica sintassi Nginx e riavvia il servizio
      shell: nginx -t
      notify: Restart Nginx

  handlers:
    - name: Restart Nginx
      systemd:
        name: nginx
        state: restarted
        enabled: yes
'@

Write-ProjectFile -Path "$rootFolder\ansible\playbook3_wazuh.yml" -Content @'
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
      shell: >
        grep "User: admin" -A 1 /root/wazuh-passwords.txt | tail -n 1 | awk '{print $2}'
      register: wazuh_password

    - name: Mostra credenziali di accesso Wazuh
      debug:
        msg: "Wazuh Dashboard URL: https://{{ ansible_host }} | User: admin | Password: {{ wazuh_password.stdout }}"

- name: Deploy e Connessione Agent su WAF e Target
  hosts: waf, target
  become: yes
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
        regexp: '<address>.*</address>'
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

Write-ProjectFile -Path "$rootFolder\ansible\waf_on.yml" -Content @'
---
- name: Attivazione Regole di Blocco WAF ModSecurity (Fase 2)
  hosts: waf
  become: yes
  tasks:
    - name: Imposta SecRuleEngine su On
      lineinfile:
        path: /etc/modsecurity/modsecurity.conf
        regexp: '^SecRuleEngine'
        line: 'SecRuleEngine On'

    - name: Riavvia Nginx per applicare le modifiche
      systemd:
        name: nginx
        state: restarted
'@

# -----------------------------------------------------------------------------
# GITHUB ACTIONS PIPELINE
# -----------------------------------------------------------------------------

Write-ProjectFile -Path "$rootFolder\.github\workflows\devsecops-pipeline.yml" -Content @'
name: DevSecOps Automation Pipeline

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:
    inputs:
      auto_destroy:
        description: 'Distruggere infrastruttura al termine?'
        type: boolean
        default: true

jobs:
  build-and-test:
    name: Provisioning, Config & E2E Security Testing
    runs-on: ubuntu-22.04

    steps:
      - name: Checkout Codice
        uses: actions/checkout@v4

      - name: Configura Credenziali AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.7

      - name: Configura Chiave SSH Privata
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/labsuser.pem
          chmod 600 ~/.ssh/labsuser.pem

      - name: Terraform Init & Apply
        run: |
          cd terraform
          terraform init
          terraform apply -auto-approve \
            -var="ssh_key_name=vockey" \
            -var="private_key_path=~/.ssh/labsuser.pem"

      - name: Setup Python e Ansible
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Installazione Dipendenze Ansible
        run: |
          python -m pip install --upgrade pip
          pip install ansible
          ansible-galaxy collection install community.docker

      - name: Attesa Istanze & Connectivity Ping
        run: |
          sleep 35
          cd ansible
          export ANSIBLE_HOST_KEY_CHECKING=False
          ansible -i inventory.ini all -m ping

      - name: Run Playbook 1 (Target Juice-Shop)
        run: |
          cd ansible
          ansible-playbook -i inventory.ini playbook1_target.yml

      - name: Run Playbook 2 (WAF Nginx ModSecurity Off)
        run: |
          cd ansible
          ansible-playbook -i inventory.ini playbook2_waf.yml

      - name: Run Playbook 3 (Wazuh SIEM Server & Agent)
        run: |
          cd ansible
          ansible-playbook -i inventory.ini playbook3_wazuh.yml

      - name: Test FASE 1 - SQLi Bypass (WAF OFF)
        run: |
          WAF_IP=$(grep 'waf_server ansible_host=' ansible/inventory.ini | awk -F'=' '{print $2}')
          echo "Target WAF IP: $WAF_IP"
          
          HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d '{"email":"'\'' OR 1=1 --","password":"password123"}' \
            "http://${WAF_IP}/rest/user/login")

          echo "HTTP Response: $HTTP_STATUS"
          if [ "$HTTP_STATUS" -eq 200 ]; then
            echo "PASSED: Login bypass riuscito con WAF disattivato."
          else
            echo "FAILED: Inatteso status $HTTP_STATUS in Fase 1."
            exit 1
          fi

      - name: Attivazione WAF (WAF ON)
        run: |
          cd ansible
          ansible-playbook -i inventory.ini waf_on.yml

      - name: Test FASE 2 - SQLi Blocked (WAF ON)
        run: |
          WAF_IP=$(grep 'waf_server ansible_host=' ansible/inventory.ini | awk -F'=' '{print $2}')
          
          HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d '{"email":"'\'' OR 1=1 --","password":"password123"}' \
            "http://${WAF_IP}/rest/user/login")

          echo "HTTP Response: $HTTP_STATUS"
          if [ "$HTTP_STATUS" -eq 403 ]; then
            echo "PASSED: Attacco bloccato con successo (403 Forbidden)."
          else
            echo "FAILED: WAF non ha bloccato l'attacco (Status: $HTTP_STATUS)."
            exit 1
          fi

      - name: Teardown Infrastruttura
        if: ${{ always() && (github.event.inputs.auto_destroy == 'true' || github.event_name == 'push') }}
        run: |
          cd terraform
          terraform destroy -auto-approve \
            -var="ssh_key_name=vockey" \
            -var="private_key_path=~/.ssh/labsuser.pem"
'@

Write-Host "`nGenerazione completata con successo! La cartella '$rootFolder' è pronta." -ForegroundColor Cyan