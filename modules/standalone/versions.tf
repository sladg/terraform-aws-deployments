terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}
