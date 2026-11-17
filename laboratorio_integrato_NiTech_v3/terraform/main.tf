module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  az                  = "us-east-1a"
  environment         = "laboratorio-integrato-nitech"
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

/*module "s3" {
  source               = "./modules/s3"
  tf_state_bucket_name = "devsecops-lab-tfstate-${random_string.suffix.result}"
  waf_logs_bucket_name = "devsecops-lab-waf-logs-${random_string.suffix.result}"
  environment          = "devsecops-lab"
}

# Generatore casuale necessario perché i nomi dei bucket S3 devono essere univoci a livello globale su AWS
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}*/