# Genera un suffisso casuale perché i nomi dei bucket S3 devono essere unici al mondo
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Creazione del bucket S3 (es. per log SIEM o script di configurazione)
resource "aws_s3_bucket" "lab_bucket" {
  bucket = "nitech-lab-storage-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "NiTech-Lab-Bucket"
    Environment = "Lab"
  }
}

# Blocca qualsiasi accesso pubblico al bucket (best practice fondamentale)
resource "aws_s3_bucket_public_access_block" "lab_bucket_pab" {
  bucket = aws_s3_bucket.lab_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Abilita la cifratura automatica dei file salvati nel bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "lab_bucket_sse" {
  bucket = aws_s3_bucket.lab_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Abilita il versioning (utile per recuperare file sovrascritti o cancellati)
resource "aws_s3_bucket_versioning" "lab_bucket_versioning" {
  bucket = aws_s3_bucket.lab_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}