variable "kubeconfig" {
  type    = string
  default = "~/.kube/config"
}

variable "stage" {
  type = string
  validation {
    condition     = contains(["bootstrap", "platform", "app"], var.stage)
    error_message = "stage must be bootstrap, platform, or app"
  }
}

variable "acr" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "model_version" {
  type = string
}

variable "public_ip_name" {
  type = string
}

variable "public_host" {
  type = string
}

variable "resource_group" {
  type = string
}

variable "allowed_cidr" {
  type = string
}

variable "runner_cidr" {
  type = string
}

variable "cluster_name" {
  type = string
}
