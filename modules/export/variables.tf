variable "project_name" {
  type        = string
  description = "The name of the project"
}

variable "project_domain" {
  type        = string
  description = "The domain name for the project."
  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}(\\.[a-z0-9-]{1,63})*$", var.project_domain))
    error_message = "The domain name must be a valid domain name"
  }
}

variable "environment" {
  type        = string
  description = "The environment for the project. Used for naming and tagging resources."
  default     = "local"
}

variable "region" {
  type        = string
  description = "The AWS where to deploy."
  default     = "eu-central-1"
}

variable "zone_domain" {
  type        = string
  description = "The domain of Route53 zone to use. Defaults to {project_domain}"
  default     = ""
}

variable "source_dir" {
  type        = string
  description = "The folder containing static files to be uploaded to S3. Defaults to `{cwd}/out`"
  default     = ""
}

variable "invalidate_on_deploy" {
  type        = bool
  description = "Invalidate the CloudFront cache on deployment."
  default     = true
}

locals {
  zone_domain = var.zone_domain != "" ? var.zone_domain : var.project_domain
  source_dir  = var.source_dir != "" ? var.source_dir : "${path.cwd}/out"
  region      = var.region
  tags = {
    Name        = var.project_name
    Env         = var.environment
    Description = "Managed by Terraform"
  }
}
