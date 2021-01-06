#############################################################################
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

#############################################################################
## Setup Folder, Tag Category, and Tag(s)
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
resource "vsphere_folder" "vm_folder" {
  path          = "k8s-deployer-${var.cluster_name}-vms"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
  tags          = [vsphere_tag.tag.id]
}

## [OPTIONAL] Create new content Library - used if manually creating new VMs from the OVA, primarily in testing
##resource "vsphere_content_library" "library" {
##  name            = "K8sDeployer"
##  storage_backing = [data.vsphere_datastore.datastore.id]
##  description     = "Primarily Fedora Core OS images to deploy Kubernetes"
##}
#### Upload FCOS OVA to the new content library
##resource "vsphere_content_library_item" "fcos" {
##  name        = "FCOS ${var.fcos_version}"
##  description = "Fedora CoreOS ${var.fcos_version} template"
##  library_id  = vsphere_content_library.library.id
##  file_url    = "/tmp/.k8s-deployer/cache/fedora-coreos-${var.fcos_version}-vmware.x86_64.ova"
##}

#############################################################################
## Create template VM from OVA

data "template_file" "template_vm_ignition_init" {
  template = file("./templates/template_ignition.yaml")
  vars = {
    cluster_name   = var.cluster_name
    ssh_public_key = tls_private_key.cluster_new_key.public_key_openssh
  }
}
resource "local_file" "template_vm_ignition_file" {
  depends_on = [data.template_file.template_vm_ignition_init]
  content    = data.template_file.template_vm_ignition_init.rendered
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.yaml"
}
resource "null_resource" "template_vm_ignition_init_fcct" {
  depends_on = [local_file.template_vm_ignition_file]
  provisioner "local-exec" {
    command = "fcct -o ${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.ign ${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.yaml"
  }
}
data "local_file" "template_vm_ignition_init_fcct" {
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/template_vm-ignition.ign"
  depends_on = [null_resource.template_vm_ignition_init_fcct]
}
resource "vsphere_virtual_machine" "templateVM" {
  depends_on       = [data.local_file.template_vm_ignition_init_fcct]
  tags             = [vsphere_tag.tag.id]
  folder           = vsphere_folder.vm_folder.path
  name             = "${var.cluster_name}-template"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datacenter_id    = data.vsphere_datacenter.dc.id
  datastore_id     = data.vsphere_datastore.datastore.id
  host_system_id   = data.vsphere_host.host.id

  num_cpus         = var.k8s_template_vm_cpu_count
  memory           = var.k8s_template_vm_memory_size
  guest_id         = "coreos64Guest"
  enable_disk_uuid = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_ip_timeout   = 0
  wait_for_guest_net_routable = false

  ovf_deploy {
    local_ovf_path       = "/tmp/.k8s-deployer/cache/fedora-coreos-${var.fcos_version}-vmware.x86_64.ova"
    disk_provisioning    = "thin"
    ip_protocol          = "IPV4"
    ip_allocation_policy = "STATIC_MANUAL"
    ovf_network_map = {
      "vmxnet3" = data.vsphere_network.network.id
    }
  }

  extra_config = {
    "guestinfo.ignition.config.data"          = base64encode(data.local_file.template_vm_ignition_init_fcct.content)
    "guestinfo.ignition.config.data.encoding" = "base64"
    "guestinfo.hostname"                      = "${var.cluster_name}-template"
  }

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = "vmxnet3"
  }

  ## This template VM needs to be shutdown before being cloned to another VM
  provisioner "local-exec" {
    command = "govc vm.power -off=true ${var.cluster_name}-template && sleep 10"

    environment = {
      GOVC_URL      = var.vsphere_server
      GOVC_USERNAME = var.vsphere_user
      GOVC_PASSWORD = var.vsphere_password

      GOVC_INSECURE = "true"
    }
  }
}

#############################################################################
## Create Bootstrap node

data "template_file" "bootstrap_vm_ignition_init" {
  template = file("./templates/bootstrap_ignition.yaml")
  vars = {
    cluster_name   = var.cluster_name
    ssh_public_key = tls_private_key.cluster_new_key.public_key_openssh
  }
}
resource "local_file" "bootstrap_vm_ignition_file" {
  depends_on = [data.template_file.bootstrap_vm_ignition_init]
  content    = data.template_file.bootstrap_vm_ignition_init.rendered
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/bootstrap_vm-ignition.yaml"
}
resource "null_resource" "bootstrap_vm_ignition_init_fcct" {
  depends_on = [local_file.bootstrap_vm_ignition_file]
  provisioner "local-exec" {
    command = "fcct -o ${var.generationDir}/.${var.cluster_name}.${var.domain}/bootstrap_vm-ignition.ign ${var.generationDir}/.${var.cluster_name}.${var.domain}/bootstrap_vm-ignition.yaml"
  }
}
data "local_file" "bootstrap_vm_ignition_init_fcct" {
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/bootstrap_vm-ignition.ign"
  depends_on = [null_resource.bootstrap_vm_ignition_init_fcct]
}
data "vsphere_virtual_machine" "templateVM" {
  depends_on    = [vsphere_virtual_machine.templateVM]
  name          = "${var.cluster_name}-template"
  datacenter_id = data.vsphere_datacenter.dc.id
}
resource "vsphere_virtual_machine" "bootstrapVM" {
  depends_on       = [data.vsphere_virtual_machine.templateVM]
  name             = "${var.cluster_name}-bootstrap"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus         = var.k8s_bootstrap_cpu_count
  memory           = var.k8s_bootstrap_memory_size
  guest_id         = "coreos64Guest"
  enable_disk_uuid = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_net_routable = false

  scsi_type = data.vsphere_virtual_machine.templateVM.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.templateVM.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = var.k8s_bootstrap_disk_size
    eagerly_scrub    = data.vsphere_virtual_machine.templateVM.disks.0.eagerly_scrub
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.templateVM.id
  }

  extra_config = {
    "guestinfo.ignition.config.data"           = base64encode(data.local_file.bootstrap_vm_ignition_init_fcct.content)
    "guestinfo.ignition.config.data.encoding"  = "base64"
    "guestinfo.hostname"                       = "${var.cluster_name}-bootstrap"
    "guestinfo.afterburn.initrd.network-kargs" = lookup(var.k8s_bootstrap_vm_network_config, "type") != "dhcp" ? "ip=${lookup(var.k8s_bootstrap_vm_network_config, "ip")}:${lookup(var.k8s_bootstrap_vm_network_config, "server_id")}:${lookup(var.k8s_bootstrap_vm_network_config, "gateway")}:${lookup(var.k8s_bootstrap_vm_network_config, "subnet")}:${var.cluster_name}-bootstrap:${lookup(var.k8s_bootstrap_vm_network_config, "interface")}:off" : "ip=::::${var.cluster_name}-bootstrap:ens192:on"
  }
  tags   = [vsphere_tag.tag.id]
  folder = vsphere_folder.vm_folder.path
}

#############################################################################
## Create Orchestrator Nodes

data "template_file" "orchestrator_vm_ignition_init" {
  template = file("./templates/orchestrator_ignition.yaml")
  count    = var.k8s_orchestrator_node_count
  vars = {
    count          = count.index
    cluster_name   = var.cluster_name
    ssh_public_key = tls_private_key.cluster_new_key.public_key_openssh
  }
}
resource "local_file" "orchestrator_vm_ignition_file" {
  depends_on = [data.template_file.orchestrator_vm_ignition_init]
  count      = var.k8s_orchestrator_node_count
  content    = element(data.template_file.orchestrator_vm_ignition_init.*.rendered, count.index)
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/orchestrator_vm_${count.index}-ignition.yaml"
}
resource "null_resource" "orchestrator_vm_ignition_init_fcct" {
  depends_on = [local_file.orchestrator_vm_ignition_file]
  count      = var.k8s_orchestrator_node_count
  provisioner "local-exec" {
    command = "fcct -o ${var.generationDir}/.${var.cluster_name}.${var.domain}/orchestrator_vm_${count.index}-ignition.ign ${var.generationDir}/.${var.cluster_name}.${var.domain}/orchestrator_vm_${count.index}-ignition.yaml"
  }
}
data "local_file" "orchestrator_vm_ignition_init_fcct" {
  count      = var.k8s_orchestrator_node_count
  depends_on = [null_resource.orchestrator_vm_ignition_init_fcct]
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/orchestrator_vm_${count.index}-ignition.ign"
}
resource "vsphere_virtual_machine" "orchestratorVMs" {
  depends_on = [data.vsphere_virtual_machine.templateVM, data.local_file.orchestrator_vm_ignition_init_fcct]
  count      = var.k8s_orchestrator_node_count

  name             = "${var.cluster_name}-orch-${count.index}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus         = var.k8s_orchestrator_cpu_count
  memory           = var.k8s_orchestrator_memory_size
  guest_id         = "coreos64Guest"
  enable_disk_uuid = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_net_routable = false

  scsi_type = data.vsphere_virtual_machine.templateVM.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.templateVM.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = var.k8s_orchestrator_disk_size
    eagerly_scrub    = data.vsphere_virtual_machine.templateVM.disks.0.eagerly_scrub
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.templateVM.id
  }

  extra_config = {
    "guestinfo.ignition.config.data"           = base64encode(element(data.local_file.orchestrator_vm_ignition_init_fcct.*.content, count.index))
    "guestinfo.ignition.config.data.encoding"  = "base64"
    "guestinfo.hostname"                       = "${var.cluster_name}-orch-${count.index}"
    "guestinfo.afterburn.initrd.network-kargs" = lookup(var.k8s_orchestrator_network_config, "orchestrator_${count.index}_type") != "dhcp" ? "ip=${lookup(var.k8s_orchestrator_network_config, "orchestrator_${count.index}_ip")}:${lookup(var.k8s_orchestrator_network_config, "orchestrator_${count.index}_server_id")}:${lookup(var.k8s_orchestrator_network_config, "orchestrator_${count.index}_gateway")}:${lookup(var.k8s_orchestrator_network_config, "orchestrator_${count.index}_subnet")}:${var.cluster_name}-orch-${count.index}:${lookup(var.k8s_orchestrator_network_config, "orchestrator_${count.index}_interface")}:off" : "ip=::::${var.cluster_name}-orch-${count.index}:ens192:on"
  }
  tags   = [vsphere_tag.tag.id]
  folder = vsphere_folder.vm_folder.path
}

#############################################################################
## Create Infrastructure Nodes

data "template_file" "infra_node_vm_ignition_init" {
  template = file("./templates/infra_ignition.yaml")
  count    = var.k8s_infra_node_count
  vars = {
    count          = count.index
    cluster_name   = var.cluster_name
    ssh_public_key = tls_private_key.cluster_new_key.public_key_openssh
  }
}
resource "local_file" "infra_node_vm_ignition_file" {
  depends_on = [data.template_file.infra_node_vm_ignition_init]
  count      = var.k8s_infra_node_count
  content    = element(data.template_file.infra_node_vm_ignition_init.*.rendered, count.index)
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/infra_vm_${count.index}-ignition.yaml"
}
resource "null_resource" "infra_node_vm_ignition_init_fcct" {
  depends_on = [local_file.infra_node_vm_ignition_file]
  count      = var.k8s_infra_node_count
  provisioner "local-exec" {
    command = "fcct -o ${var.generationDir}/.${var.cluster_name}.${var.domain}/infra_vm_${count.index}-ignition.ign ${var.generationDir}/.${var.cluster_name}.${var.domain}/infra_vm_${count.index}-ignition.yaml"
  }
}
data "local_file" "infra_node_vm_ignition_init_fcct" {
  count      = var.k8s_infra_node_count
  depends_on = [null_resource.infra_node_vm_ignition_init_fcct]
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/infra_vm_${count.index}-ignition.ign"
}
resource "vsphere_virtual_machine" "infra_nodeVMs" {
  depends_on = [data.vsphere_virtual_machine.templateVM, data.local_file.infra_node_vm_ignition_init_fcct]
  count      = var.k8s_infra_node_count

  name             = "${var.cluster_name}-orch-${count.index}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus         = var.k8s_infra_node_cpu_count
  memory           = var.k8s_infra_node_memory_size
  guest_id         = "coreos64Guest"
  enable_disk_uuid = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_net_routable = false

  scsi_type = data.vsphere_virtual_machine.templateVM.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.templateVM.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = var.k8s_infra_node_disk_size
    eagerly_scrub    = data.vsphere_virtual_machine.templateVM.disks.0.eagerly_scrub
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.templateVM.id
  }

  extra_config = {
    "guestinfo.ignition.config.data"           = base64encode(element(data.local_file.infra_node_vm_ignition_init_fcct.*.content, count.index))
    "guestinfo.ignition.config.data.encoding"  = "base64"
    "guestinfo.hostname"                       = "${var.cluster_name}-orch-${count.index}"
    "guestinfo.afterburn.initrd.network-kargs" = lookup(var.k8s_infra_node_network_config, "infra_node_${count.index}_type") != "dhcp" ? "ip=${lookup(var.k8s_infra_node_network_config, "infra_node_${count.index}_ip")}:${lookup(var.k8s_infra_node_network_config, "infra_node_${count.index}_server_id")}:${lookup(var.k8s_infra_node_network_config, "infra_node_${count.index}_gateway")}:${lookup(var.k8s_infra_node_network_config, "infra_node_${count.index}_subnet")}:${var.cluster_name}-orch-${count.index}:${lookup(var.k8s_infra_node_network_config, "infra_node_${count.index}_interface")}:off" : "ip=::::${var.cluster_name}-orch-${count.index}:ens192:on"
  }
  tags   = [vsphere_tag.tag.id]
  folder = vsphere_folder.vm_folder.path
}

#############################################################################
## Create Application Nodes

data "template_file" "app_node_vm_ignition_init" {
  template = file("./templates/app_ignition.yaml")
  count    = var.k8s_app_node_count
  vars = {
    count          = count.index
    cluster_name   = var.cluster_name
    ssh_public_key = tls_private_key.cluster_new_key.public_key_openssh
  }
}
resource "local_file" "app_node_vm_ignition_file" {
  depends_on = [data.template_file.app_node_vm_ignition_init]
  count      = var.k8s_app_node_count
  content    = element(data.template_file.app_node_vm_ignition_init.*.rendered, count.index)
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/app_vm_${count.index}-ignition.yaml"
}
resource "null_resource" "app_node_vm_ignition_init_fcct" {
  depends_on = [local_file.app_node_vm_ignition_file]
  count      = var.k8s_app_node_count
  provisioner "local-exec" {
    command = "fcct -o ${var.generationDir}/.${var.cluster_name}.${var.domain}/app_vm_${count.index}-ignition.ign ${var.generationDir}/.${var.cluster_name}.${var.domain}/app_vm_${count.index}-ignition.yaml"
  }
}
data "local_file" "app_node_vm_ignition_init_fcct" {
  count      = var.k8s_app_node_count
  depends_on = [null_resource.app_node_vm_ignition_init_fcct]
  filename   = "${var.generationDir}/.${var.cluster_name}.${var.domain}/app_vm_${count.index}-ignition.ign"
}
resource "vsphere_virtual_machine" "app_nodeVMs" {
  depends_on = [data.vsphere_virtual_machine.templateVM, data.local_file.app_node_vm_ignition_init_fcct]
  count      = var.k8s_app_node_count

  name             = "${var.cluster_name}-orch-${count.index}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus         = var.k8s_app_node_cpu_count
  memory           = var.k8s_app_node_memory_size
  guest_id         = "coreos64Guest"
  enable_disk_uuid = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_net_routable = false

  scsi_type = data.vsphere_virtual_machine.templateVM.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.templateVM.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = var.k8s_app_node_disk_size
    eagerly_scrub    = data.vsphere_virtual_machine.templateVM.disks.0.eagerly_scrub
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.templateVM.id
  }

  extra_config = {
    "guestinfo.ignition.config.data"           = base64encode(element(data.local_file.app_node_vm_ignition_init_fcct.*.content, count.index))
    "guestinfo.ignition.config.data.encoding"  = "base64"
    "guestinfo.hostname"                       = "${var.cluster_name}-orch-${count.index}"
    "guestinfo.afterburn.initrd.network-kargs" = lookup(var.k8s_app_node_network_config, "app_node_${count.index}_type") != "dhcp" ? "ip=${lookup(var.k8s_app_node_network_config, "app_node_${count.index}_ip")}:${lookup(var.k8s_app_node_network_config, "app_node_${count.index}_server_id")}:${lookup(var.k8s_app_node_network_config, "app_node_${count.index}_gateway")}:${lookup(var.k8s_app_node_network_config, "app_node_${count.index}_subnet")}:${var.cluster_name}-orch-${count.index}:${lookup(var.k8s_app_node_network_config, "app_node_${count.index}_interface")}:off" : "ip=::::${var.cluster_name}-orch-${count.index}:ens192:on"
  }
  tags   = [vsphere_tag.tag.id]
  folder = vsphere_folder.vm_folder.path
}
