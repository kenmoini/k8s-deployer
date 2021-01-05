## Generate new cluster SSH Keys
resource "tls_private_key" "cluster_new_key" {
  algorithm = "RSA"
}
resource "local_file" "cluster_new_priv_file" {
  content         = tls_private_key.cluster_new_key.private_key_pem
  filename        = "${var.generationDir}/.${var.cluster_name}.${var.domain}/priv.pem"
  file_permission = "0600"
}
resource "local_file" "cluster_new_pub_file" {
  content  = tls_private_key.cluster_new_key.public_key_openssh
  filename = "${var.generationDir}/.${var.cluster_name}.${var.domain}/pub.key"
}

## Gather data, need IDs
data "vsphere_datacenter" "dc" {
  name = var.vmware_datacenter
}
data "vsphere_datastore" "datastore" {
  name          = var.vmware_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}
data "vsphere_compute_cluster" "cluster" {
  name          = var.vmware_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}
data "vsphere_network" "network" {
  name          = var.vmware_network
  datacenter_id = data.vsphere_datacenter.dc.id
}
data "vsphere_host" "host" {
  name          = var.vmware_ova_host
  datacenter_id = data.vsphere_datacenter.dc.id
}

## Setup Tag Category and Tag(s)
resource "vsphere_tag_category" "category" {
  name        = "k8s-deployer-${var.cluster_name}"
  description = "Added by k8s-deployer do not remove"
  cardinality = "SINGLE"

  associable_types = [
    "VirtualMachine",
    "ResourcePool",
    "Folder",
    "com.vmware.content.Library",
    "com.vmware.content.library.item"
  ]
}
resource "vsphere_tag" "tag" {
  name        = var.cluster_name
  category_id = vsphere_tag_category.category.id
  description = "Added by k8s-deployer do not remove"
}

## Create new content Library
##resource "vsphere_content_library" "library" {
##  name            = "K8sDeployer"
##  storage_backing = [data.vsphere_datastore.datastore.id]
##  description     = "Primarily Fedora Core OS images to deploy Kubernetes"
##}
##
#### Upload FCOS OVA to the new content library
##resource "vsphere_content_library_item" "fcos" {
##  name        = "FCOS ${var.fcos_version}"
##  description = "Fedora CoreOS ${var.fcos_version} template"
##  library_id  = vsphere_content_library.library.id
##  file_url    = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${var.fcos_version}/x86_64/fedora-coreos-${var.fcos_version}-vmware.x86_64.ova"
##}

##output "fcostemplate" {
##  value      = data.vsphere_virtual_machine.fcostemplate
##  depends_on = [vsphere_content_library_item.fcos]
##}
##
##data "vsphere_virtual_machine" "fcostemplate" {
##  name          = "FCOS ${var.fcos_version}"
##  datacenter_id = data.vsphere_datacenter.dc.id
##  depends_on    = [vsphere_content_library_item.fcos]
##}
## Upload CentOS 8 ISO to the new content library (?)

## Create template VM from OVA

data "template_file" "ignition_init" {
  template = file("./templates/template_ignition.yaml")
  vars = {
    cluster_name   = var.cluster_name
    ssh_public_key = tls_private_key.cluster_new_key.public_key_openssh
  }
}
resource "local_file" "template_vm_ignition_file" {
  depends_on = [data.template_file.ignition_init]
  content    = data.template_file.ignition_init.rendered
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.yaml"
}
resource "null_resource" "ignition_init_fcct" {
  depends_on = [local_file.template_vm_ignition_file]
  provisioner "local-exec" {
    command = "fcct -o ${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.ign ${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.yaml"
  }
}
data "local_file" "ignition_init_fcct" {
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.ign"
  depends_on = [null_resource.ignition_init_fcct]
}
resource "vsphere_virtual_machine" "templateVM" {
  depends_on       = [data.local_file.ignition_init_fcct]
  tags             = [vsphere_tag.tag.id]
  name             = "${var.cluster_name}-template"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datacenter_id    = data.vsphere_datacenter.dc.id
  datastore_id     = data.vsphere_datastore.datastore.id
  host_system_id   = data.vsphere_host.host.id

  num_cpus             = var.k8s_template_vm_cpu_count
  num_cores_per_socket = var.k8s_template_vm_core_count
  memory               = var.k8s_template_vm_memory_size
  guest_id             = "coreos64Guest"
  enable_disk_uuid     = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_ip_timeout   = 0
  wait_for_guest_net_routable = false

  ovf_deploy {
    local_ovf_path       = "/tmp/.k8s-deployer/cache/fedora-coreos-${var.fcos_version}-vmware.x86_64.ova"
    disk_provisioning    = "thin"
    ip_protocol          = "IPV4"
    ip_allocation_policy = "STATIC_MANUAL"
    ovf_network_map = {
      "ESX-port-1" = data.vsphere_network.network.id
    }
  }

  extra_config = {
    "guestinfo.ignition.config.data"          = base64encode(data.local_file.ignition_init_fcct.content)
    "guestinfo.ignition.config.data.encoding" = "base64"
  }

  provisioner "local-exec" {
    command = "govc vm.power -off=true ${var.cluster_name}-template"

    environment = {
      GOVC_URL      = var.vsphere_server
      GOVC_USERNAME = var.vsphere_user
      GOVC_PASSWORD = var.vsphere_password

      GOVC_INSECURE = "true"
    }
  }
}

#data "vsphere_virtual_machine" "templateVM" {
#  name          = "${var.cluster_name}-template"
#  datacenter_id = data.vsphere_datacenter.dc.id
#  depends_on    = [vsphere_virtual_machine.templateVM]
#}

## Create Hub Node (Load Balancer, HTTP for ignition, DNS)
#resource "vsphere_virtual_machine" "bootstrap" {
#  depends_on       = [data.vsphere_virtual_machine.templateVM]
#  name             = "${var.cluster_name}-bootstrap"
#  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
#  datastore_id     = data.vsphere_datastore.datastore.id
#
#  num_cpus             = var.k8s_app_bootstrap_cpu_count
#  num_cores_per_socket = var.k8s_bootstrap_core_count
#  memory               = var.k8s_bootstrap_memory_size
#  guest_id             = "coreos64Guest"
#  enable_disk_uuid     = "true"
#
#  wait_for_guest_net_timeout  = 0
#  wait_for_guest_net_routable = false
#
#  scsi_type = data.vsphere_virtual_machine.templateVM.scsi_type
#
#  network_interface {
#    network_id   = data.vsphere_network.network.id
#    adapter_type = data.vsphere_virtual_machine.templateVM.network_interface_types[0]
#  }
#
#  disk {
#    label            = "disk0"
#    size             = var.k8s_bootstrap_disk_size
#    eagerly_scrub    = data.vsphere_virtual_machine.templateVM.disks.0.eagerly_scrub
#    thin_provisioned = true
#  }
#
#  clone {
#    template_uuid = data.vsphere_virtual_machine.templateVM.id
#
#    customize {
#      linux_options {
#        host_name = "${var.cluster_name}-bootstrap"
#        domain    = var.domain
#      }
#
#      network_interface {
#        ipv4_address = "192.168.42.82"
#        ipv4_netmask = 24
#      }
#
#      ipv4_gateway = "192.168.42.1"
#    }
#  }
#
#  extra_config = {
#    "guestinfo.ignition.config.data"          = base64encode(var.k8s_bootstrap_ignition)
#    "guestinfo.ignition.config.data.encoding" = "base64"
#    "guestinfo.hostname"                      = "${var.cluster_name}-bootstrap"
#  }
#  tags = [vsphere_tag.tag.id]
#}
## Create Orchestrator Nodes

## Create Application Nodes