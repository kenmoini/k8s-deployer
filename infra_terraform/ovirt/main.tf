terraform {
  required_providers {
    ovirt = {
      source  = "ovirt"
      version = "0.4.2"
    }
  }
}

provider "ovirt" {
  username = "admin@internal"
  url      = "https://rhvm.example.com/ovirt-engine/api"
  password = "password"
}


data "ovirt_clusters" "filtered_clusters" {
  name_regex = "*"

  search = {
    criteria       = "architecture = x86_64"
    max            = 2
    case_sensitive = false
  }
}
