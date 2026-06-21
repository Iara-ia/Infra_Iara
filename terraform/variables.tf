variable "region" {
  description = "Região AWS (Brasil-first: considere sa-east-1; us-east-1 cobre mais serviços/preço)."
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Ambiente (dev|staging|prod)."
  type        = string
  default     = "dev"
}

variable "project" {
  type    = string
  default = "iara"
}

// Placeholders preenchidos no deploy real.
variable "db_master_username" {
  type    = string
  default = "iara"
}

variable "domain_name" {
  description = "Domínio do CloudFront (opcional no scaffold)."
  type        = string
  default     = ""
}
