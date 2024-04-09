terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.40"
      configuration_aliases = [aws.virginia]
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}
