variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "mlp"
}

variable "node_image" {
  description = "Pinned kind node image (must include the digest)."
  type        = string
  default     = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"
}

variable "kubeconfig_path" {
  description = "Where the kind provider writes the kubeconfig file."
  type        = string
  default     = ""
}

variable "registry_host" {
  description = "Registry hostname as seen from the host (kind-config mirror target)."
  type        = string
  default     = "localhost:5001"
}

variable "registry_container_host" {
  description = "Registry hostname as seen from inside kind nodes."
  type        = string
  default     = "kind-registry:5000"
}

variable "port_mappings" {
  description = "Host ports for service NodePorts (hostPort -> containerPort)."
  type        = map(number)
  default = {
    "8080" = 30080
    "8081" = 30081
    "3000" = 30030
    "5000" = 30500
    "9000" = 30900
    "9001" = 30901
    "9090" = 30090
    "9093" = 30093
  }
}
