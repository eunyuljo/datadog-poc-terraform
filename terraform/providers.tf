# providers.tf
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Purpose   = "datadog-poc"
      Owner     = var.owner
    }
  }
}
