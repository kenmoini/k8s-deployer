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
