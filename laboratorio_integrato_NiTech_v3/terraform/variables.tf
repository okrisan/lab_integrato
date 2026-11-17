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