variable "ssh_key_name" {
  description = "Nome della Key Pair su AWS"
  type        = string
  default     = "nitech_lab"
}

variable "private_key_path" {
  description = "Percorso locale della chiave privata SSH"
  type        = string
  default     = "~/.ssh/nitech_lab"
}