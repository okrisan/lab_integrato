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
3. Esegui i playbook in `ansible/` e passa al red team.
4. `cd terraform && terraform apply -var="phase=phase2" -auto-approve`
5. Aggiorna `ansible/hosts.ini` (modalitÃ  Bastion), riesegui i playbook e verifica il blocco 403 + alert Wazuh (Fase 2).
6. `terraform destroy -var="phase=phase2" -auto-approve` a fine sessione.