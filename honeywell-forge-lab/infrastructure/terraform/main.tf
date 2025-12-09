# Honeywell Forge Cognition - Terraform Infrastructure
# Provisions VMs for lab environment (optional - if using cloud/vSphere)
#
# Supported providers:
#   - vSphere (ESXi) - for on-prem lab
#   - AWS (optional)
#   - Azure (optional)
#
# Usage:
#   cd terraform
#   terraform init
#   terraform plan
#   terraform apply
#

terraform {
  required_version = ">= 1.0"

  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================
variable "vsphere_server" {
  description = "vSphere server address"
  type        = string
}

variable "vsphere_user" {
  description = "vSphere username"
  type        = string
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  sensitive   = true
}

variable "datacenter" {
  description = "vSphere datacenter name"
  type        = string
  default     = "Datacenter"
}

variable "cluster" {
  description = "vSphere cluster name"
  type        = string
  default     = "Cluster"
}

variable "datastore" {
  description = "vSphere datastore name"
  type        = string
}

variable "network" {
  description = "vSphere network name"
  type        = string
  default     = "VM Network"
}

variable "template" {
  description = "VM template name (Ubuntu 22.04 recommended)"
  type        = string
  default     = "ubuntu-22.04-template"
}

variable "vm_name" {
  description = "Name for the GPU VM"
  type        = string
  default     = "forge-lab-gpu"
}

variable "vm_cpus" {
  description = "Number of CPUs"
  type        = number
  default     = 8
}

variable "vm_memory" {
  description = "Memory in MB"
  type        = number
  default     = 32768  # 32GB
}

variable "vm_disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 200
}

variable "ssh_public_key" {
  description = "SSH public key for access"
  type        = string
}

# =============================================================================
# Provider Configuration
# =============================================================================
provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password
  allow_unverified_ssl = true
}

# =============================================================================
# Data Sources
# =============================================================================
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.dc.id
}

# =============================================================================
# GPU VM Resource
# =============================================================================
resource "vsphere_virtual_machine" "gpu_vm" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.vm_cpus
  memory   = var.vm_memory

  guest_id = data.vsphere_virtual_machine.template.guest_id
  firmware = data.vsphere_virtual_machine.template.firmware

  # Network
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = "vmxnet3"
  }

  # Disk
  disk {
    label            = "disk0"
    size             = var.vm_disk_size
    thin_provisioned = true
  }

  # Clone from template
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = var.vm_name
        domain    = "local"
      }

      network_interface {
        ipv4_address = ""  # DHCP
      }
    }
  }

  # GPU Passthrough Configuration
  # NOTE: This requires manual setup in vSphere to enable GPU passthrough
  # The pci_device_id needs to be obtained from your ESXi host
  #
  # To find the GPU PCI device ID:
  #   1. SSH to ESXi host
  #   2. Run: lspci -v | grep -i nvidia
  #   3. Note the device ID (e.g., 0000:3b:00.0)
  #
  # Uncomment and configure after identifying your GPU:
  # pci_device_id = ["0000:3b:00.0"]

  # Cloud-init for initial setup
  extra_config = {
    "guestinfo.userdata" = base64encode(<<-EOF
      #cloud-config
      users:
        - name: root
          ssh_authorized_keys:
            - ${var.ssh_public_key}
      package_update: true
      packages:
        - curl
        - wget
        - git
        - vim
    EOF
    )
    "guestinfo.userdata.encoding" = "base64"
  }

  lifecycle {
    ignore_changes = [
      clone[0].customize[0].network_interface,
    ]
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "vm_name" {
  description = "Name of the created VM"
  value       = vsphere_virtual_machine.gpu_vm.name
}

output "vm_ip" {
  description = "IP address of the VM"
  value       = vsphere_virtual_machine.gpu_vm.default_ip_address
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh root@${vsphere_virtual_machine.gpu_vm.default_ip_address}"
}

output "next_steps" {
  description = "Next steps after VM creation"
  value       = <<-EOF

    VM created successfully!

    Next steps:
    1. Enable GPU passthrough in vSphere for this VM
    2. Update Ansible inventory with the VM IP:
       sed -i 's/ansible_host: .*/ansible_host: ${vsphere_virtual_machine.gpu_vm.default_ip_address}/' ../ansible/inventory/lab.yaml
    3. Run Ansible deployment:
       ../scripts/deploy-to-lab.sh

  EOF
}
