terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.67.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }
}
