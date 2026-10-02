variable "registry_name" {
  description = "Name of the local registry container."
  type        = string
  default     = "kind-registry"
}

variable "registry_port" {
  description = "Host port publishing the registry."
  type        = number
  default     = 5001
}

variable "registry_image" {
  description = "Pinned registry image (must include the digest)."
  type        = string
  default     = "registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373"
}

variable "script_path" {
  description = "Path to the idempotent registry bootstrap script."
  type        = string
  default     = "../../../scripts/registry.sh"
}
