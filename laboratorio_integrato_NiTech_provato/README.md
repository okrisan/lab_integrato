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