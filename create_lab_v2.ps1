$ProjectRoot = "laboratorio_integrato_NiTech_v2"

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

Write-Host "Generazione progetto $ProjectRoot (Modalita WAF Toggle) in corso..." -ForegroundColor Cyan

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
# AWS Cloud Security & DevSecOps Lab (WAF Toggle Edition)

Architettura Zero-Trust su AWS Academy Learner Lab (`us-east-1`) con Target isolato in Subnet Privata e commutazione dinamica delle policy WAF.

## Architettura
- **Terraform (IaC)**: VPC (`10.0.0.0/16`), Subnet Pubblica (WAF + SIEM), Subnet Privata (Target Juice Shop), NAT Gateway e Security Groups restrittivi.
- **Ansible (Config Management)**:
  - `playbook1_target.yml`: Deploy OWASP Juice Shop (Docker) in Subnet Privata.
  - `playbook2_waf.yml`: Deploy Nginx + ModSecurity v3 + OWASP CRS v4 (inizializzato con `SecRuleEngine Off`).
  - `playbook3_wazuh.yml`: Deploy Wazuh SIEM All-in-One + Agent su WAF e Target.
  - `waf_off.yml` / `waf_on.yml`: Switch immediato tra Pass-Through (Fase 1) e Blocking Mode (Fase 2).

## Workflow Rapido (da WSL Debian)
1. `cd terraform && terraform init && terraform apply -auto-approve`
2. Inserisci gli IP generati in `ansible/hosts.ini`, `ansible/playbook2_waf.yml` e `ansible/playbook3_wazuh.yml`.
3. Esegui in sequenza `playbook1_target.yml`, `playbook2_waf.yml` e `playbook3_wazuh.yml`.
4. **FASE 1 (WAF Spento)**: Attacca `http://<WAF_PUBLIC_IP>` con SQL Injection (`' OR 1=1 --`) -> Login riuscito.
5. **FASE 2 (WAF Acceso)**: Esegui `ansible-playbook -i hosts.ini waf_on.yml` -> Ripeti l'attacco -> Blocco `403 Forbidden` e alert su Wazuh SIEM.
6. A fine sessione: `cd terraform && terraform destroy -auto-approve`.
'@

# ==========================================
# 2. FILE TERRAFORM (ARCHITETTURA ZERO-TRUST)
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
    description = "HTTP pubblico verso Reverse Proxy WAF"
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
  description = "Accesso Zero-Trust a Juice Shop in Subnet Privata"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH solo da Subnet Pubblica (Bastion WAF)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    description     = "Porta 3000 accessibile SOLO dal Security Group del WAF"
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
  subnet_id              = aws_subnet.private.id
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
  description = "IP Pubblico WAF (Punto di ingresso unico per il Red Team)"
}

output "siem_public_ip" {
  value       = aws_instance.siem.public_ip
  description = "IP Pubblico SIEM Wazuh"
}

output "siem_private_ip" {
  value       = aws_instance.siem.private_ip
  description = "IP Privato SIEM Wazuh (per configurazione Agent)"
}

output "target_private_ip" {
  value       = aws_instance.target.private_ip
  description = "IP Privato Target in Subnet Privata"
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
target_node ansible_host=<TARGET_PRIVATE_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/labsuser.pem

[target:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ubuntu@<WAF_PUBLIC_IP> -i ~/.ssh/labsuser.pem"'

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
'@

Write-LinuxFile "$ProjectRoot/ansible/playbook1_target.yml" @'
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

Write-LinuxFile "$ProjectRoot/ansible/playbook2_waf.yml" @'
---
- name: Configurazione WAF Nginx con ModSecurity v3 e OWASP CRS (Default Off per Fase 1)
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

    - name: Pre-crea file di audit log ModSecurity con permessi per Nginx (www-data)
      file:
        path: /var/log/modsec_audit.log
        state: touch
        owner: www-data
        group: adm
        mode: '0640'

    - name: Imposta SecRuleEngine su Off (FASE 1 - Pass-Through senza filtro)
      lineinfile:
        path: /etc/modsecurity/modsecurity.conf
        regexp: '^SecRuleEngine'
        line: 'SecRuleEngine Off'

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

Write-LinuxFile "$ProjectRoot/ansible/waf_off.yml" @'
---
- name: FASE 1 - Disattiva policy WAF (Modalita Pass-Through / Vulnerabile)
  hosts: waf
  become: yes
  tasks:
    - name: Imposta SecRuleEngine su Off
      lineinfile:
        path: /etc/modsecurity/modsecurity.conf
        regexp: '^SecRuleEngine'
        line: 'SecRuleEngine Off'

    - name: Riavvia Nginx per applicare la modifica
      systemd:
        name: nginx
        state: restarted
'@

Write-LinuxFile "$ProjectRoot/ansible/waf_on.yml" @'
---
- name: FASE 2 - Attiva policy WAF (Modalita Blocking / Protetta)
  hosts: waf
  become: yes
  tasks:
    - name: Imposta SecRuleEngine su On
      lineinfile:
        path: /etc/modsecurity/modsecurity.conf
        regexp: '^SecRuleEngine'
        line: 'SecRuleEngine On'

    - name: Riavvia Nginx per applicare la modifica
      systemd:
        name: nginx
        state: restarted
'@

Write-Host "`nStruttura creata con successo in ./$ProjectRoot!" -ForegroundColor Yellow