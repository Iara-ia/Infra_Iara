// ESQUELETO de IaC — não 100% deployável (placeholders de ARNs/handlers/ACM).
// Objetivo: mapear 1:1 os recursos do painel de custos serverless da IARA.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  // Backend remoto (descomente e ajuste ao provisionar o bucket/lock de estado).
  // backend "s3" {
  //   bucket         = "iara-tfstate"
  //   key            = "infra/terraform.tfstate"
  //   region         = "us-east-1"
  //   dynamodb_table = "iara-tflock"
  //   encrypt        = true
  // }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "IARA"
      Env     = var.env
      Managed = "terraform"
    }
  }
}
