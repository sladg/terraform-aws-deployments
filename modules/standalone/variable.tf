variable "project_name" {
  type        = string
  description = "The name of the project"
}

variable "project_domain" {
  type        = string
  description = "The domain name for the project."
  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}(\\.[a-z0-9-]{1,63})*$", var.domain))
    error_message = "The domain name must be a valid domain name"
  }
}

variable "environment" {
  type        = string
  description = "The environment for the project. Used for naming and tagging resources."
  default     = "local"
}

variable "zone_domain" {
  type        = string
  description = "The domain of Route53 zone to use. Defaults to {project_domain}"
  default     = ""
}

variable "healthcheck_url" {
  type        = string
  description = "The URL to check for health status."
  default     = "http://localhost:3000/api/health"
}

variable "lambda_streaming" {
  type        = bool
  description = "Enable streaming for Lambda responses."
  default     = false
}

variable "lambda_envs" {
  type        = map(string)
  description = "Environment variables for Lambda functions."
  default     = {}
}

locals {
  zone_domain = var.zone_domain != "" ? var.zone_domain : var.project_domain
  tags = {
    Name        = var.project_name
    Env         = var.environment
    Description = "Managed by Terraform"
  }
}
