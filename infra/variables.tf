variable "region" {
  type        = string
  description = "AWS region"
}

variable "az" {
  type        = string
  description = "Optional. If empty, Terraform picks the first available AZ in the region."
  default     = ""
}
