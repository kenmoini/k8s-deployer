variable "generationDir" {
  type    = string
  default = "../../.generated"
}
variable "fcos_version" {
  type    = string
  default = "33.20201201.3.0"
}

variable "vmware_datacenter" {
  type    = string
  default = "VMWDC"
}
variable "vmware_datastore" {
  type    = string
  default = "bigNVMe"
}
variable "vmware_cluster" {
  type    = string
  default = "CoreCluster"
}
variable "vmware_network" {
  type    = string
  default = "VM Network"
}
variable "vmware_ova_host" {
  type    = string
  default = "192.168.42.30"
}


variable "cluster_name" {
  type    = string
  default = "pgk8s-vmw"
}
variable "domain" {
  type    = string
  default = "kemo.labs"
}

variable "k8s_orchestrator_node_count" {
  type    = string
  default = "3"
}
variable "k8s_infra_node_count" {
  type    = string
  default = "3"
}
variable "k8s_app_node_count" {
  type    = string
  default = "2"
}

variable "k8s_template_vm_disk_size" {
  type    = string
  default = "32"
}
variable "k8s_template_vm_memory_size" {
  type    = string
  default = "16384"
}
variable "k8s_template_vm_cpu_count" {
  type    = string
  default = "1"
}
variable "k8s_template_vm_core_count" {
  type    = string
  default = "4"
}

variable "k8s_bootstrap_disk_size" {
  type    = string
  default = "32"
}
variable "k8s_bootstrap_memory_size" {
  type    = string
  default = "16384"
}
variable "k8s_bootstrap_cpu_count" {
  type    = string
  default = "1"
}
variable "k8s_bootstrap_core_count" {
  type    = string
  default = "4"
}

variable "k8s_orchestrator_cpu_count" {
  type    = string
  default = "1"
}
variable "k8s_infra_node_cpu_count" {
  type    = string
  default = "1"
}
variable "k8s_app_node_cpu_count" {
  type    = string
  default = "1"
}

variable "k8s_orchestrator_core_count" {
  type    = string
  default = "4"
}
variable "k8s_infra_node_core_count" {
  type    = string
  default = "4"
}
variable "k8s_app_node_core_count" {
  type    = string
  default = "4"
}

variable "k8s_orchestrator_memory_size" {
  type    = string
  default = "16384"
}
variable "k8s_infra_node_memory_size" {
  type    = string
  default = "16384"
}
variable "k8s_app_node_memory_size" {
  type    = string
  default = "16384"
}

variable "k8s_orchestrator_disk_size" {
  type    = string
  default = "32"
}
variable "k8s_infra_node_disk_size" {
  type    = string
  default = "32"
}
variable "k8s_app_node_disk_size" {
  type    = string
  default = "32"
}
