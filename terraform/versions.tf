# versions.tf
# Datadog PoC (Bits Detection / BIO / Workflow Automation) 검증용 인프라
# Terraform 및 provider 버전 고정
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}
