variable "aws_region" {
  description = "AWS region"
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Resource name prefix — used for all AWS resource names"
  default     = "my-role-fit"
}

variable "cors_allowed_origin" {
  description = "Allowed CORS origin"
  default     = "https://imrozzoha.com"
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "role-fit-analyzer"
    ManagedBy = "terraform"
  }
}
