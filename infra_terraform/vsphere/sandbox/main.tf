
data "vsphere_virtual_machine" "templateVM" {
  name          = "${var.cluster_name}-template"
  datacenter_id = data.vsphere_datacenter.dc.id
}
output "vmInfo" {
  value = data.vsphere_virtual_machine.templateVM
}
