variable "bucket_prefix" {
  description = "Prefix for bucket names (must stay globally unique)."
  type        = string
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
