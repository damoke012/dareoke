# Honeywell Forge Cognition - Terraform Infrastructure
# Provisions VMs for K3s lab environment on ESXi/vSphere
#
# Architecture:
#   - k3s-server: Control plane node (lightweight, no GPU)
#   - k3s-gpu-agent: Worker node with GPU passthrough
#
# Usage:
#   cd terraform
#   cp terraform.tfvars.example terraform.tfvars
#   # Edit terraform.tfvars with your values
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
  description = "vSphere/ESXi server address"
  type        = string
}

variable "vsphere_user" {
  description = "vSphere username (root for standalone ESXi)"
  type        = string
  default     = "root"
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  sensitive   = true
}

variable "datacenter" {
  description = "vSphere datacenter name (use 'ha-datacenter' for standalone ESXi)"
  type        = string
  default     = "ha-datacenter"
}

variable "datastore" {
  description = "vSphere datastore name"
  type        = string
  default     = "datastore1"
}

variable "network" {
  description = "vSphere network name"
  type        = string
  default     = "VM Network"
}

variable "resource_pool" {
  description = "Resource pool path (use 'ha-root-pool' for standalone ESXi)"
  type        = string
  default     = "ha-root-pool"
}

variable "template" {
  description = "VM template name (Ubuntu 20.04/22.04 or Rocky 9 recommended)"
  type        = string
  default     = "ubuntu-template"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

# K3s Server VM Configuration
variable "k3s_server_name" {
  description = "Name for the K3s server VM"
  type        = string
  default     = "k3s-server"
}

variable "k3s_server_cpus" {
  description = "CPUs for K3s server"
  type        = number
  default     = 4
}

variable "k3s_server_memory" {
  description = "Memory in MB for K3s server"
  type        = number
  default     = 8192  # 8GB
}

variable "k3s_server_disk_size" {
  description = "Disk size in GB for K3s server"
  type        = number
  default     = 100
}

variable "k3s_server_ip" {
  description = "Static IP for K3s server (leave empty for DHCP)"
  type        = string
  default     = ""
}

# K3s GPU Agent VM Configuration
variable "k3s_agent_name" {
  description = "Name for the K3s GPU agent VM"
  type        = string
  default     = "k3s-gpu-agent"
}

variable "k3s_agent_cpus" {
  description = "CPUs for K3s GPU agent"
  type        = number
  default     = 8
}

variable "k3s_agent_memory" {
  description = "Memory in MB for K3s GPU agent"
  type        = number
  default     = 32768  # 32GB
}

variable "k3s_agent_disk_size" {
  description = "Disk size in GB for K3s GPU agent"
  type        = number
  default     = 200
}

variable "k3s_agent_ip" {
  description = "Static IP for K3s GPU agent (leave empty for DHCP)"
  type        = string
  default     = ""
}

# GPU Configuration
variable "gpu_pci_device_id" {
  description = "PCI device ID for GPU passthrough (e.g., '0000:3b:00.0'). Leave empty to skip GPU passthrough."
  type        = string
  default     = ""
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

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.dc.id
}

# =============================================================================
# K3s Server VM (Control Plane)
# =============================================================================
resource "vsphere_virtual_machine" "k3s_server" {
  name             = var.k3s_server_name
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.k3s_server_cpus
  memory   = var.k3s_server_memory

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
    size             = var.k3s_server_disk_size
    thin_provisioned = true
  }

  # Clone from template
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = var.k3s_server_name
        domain    = "local"
      }

      network_interface {
        ipv4_address = var.k3s_server_ip != "" ? var.k3s_server_ip : null
      }
    }
  }

  # Cloud-init for initial setup
  extra_config = {
    "guestinfo.userdata" = base64encode(<<-EOF
      #cloud-config
      hostname: ${var.k3s_server_name}
      users:
        - name: root
          ssh_authorized_keys:
            - ${var.ssh_public_key}
        - name: k3s
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
      package_update: true
      packages:
        - curl
        - wget
        - git
        - vim
        - htop
        - jq
      runcmd:
        - echo "K3s Server VM ready for deployment" > /var/log/vm-init.log
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
# K3s GPU Agent VM (Worker with GPU)
# =============================================================================
resource "vsphere_virtual_machine" "k3s_gpu_agent" {
  name             = var.k3s_agent_name
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.k3s_agent_cpus
  memory   = var.k3s_agent_memory

  # Required for GPU passthrough
  memory_reservation = var.gpu_pci_device_id != "" ? var.k3s_agent_memory : null

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
    size             = var.k3s_agent_disk_size
    thin_provisioned = true
  }

  # Clone from template
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = var.k3s_agent_name
        domain    = "local"
      }

      network_interface {
        ipv4_address = var.k3s_agent_ip != "" ? var.k3s_agent_ip : null
      }
    }
  }

  # GPU Passthrough Configuration
  # NOTE: GPU passthrough requires:
  #   1. ESXi host configured for passthrough (esxcli system settings kernel set -s vga -v FALSE)
  #   2. GPU marked for passthrough in vSphere UI (Host > Configure > Hardware > PCI Devices)
  #   3. Host rebooted after enabling passthrough
  #
  # To find GPU PCI device ID, SSH to ESXi and run:
  #   lspci -v | grep -i nvidia
  #   esxcli hardware pci list | grep -A 10 -i nvidia
  #
  # Uncomment the following block after configuring GPU passthrough:
  # dynamic "pci_device_id" {
  #   for_each = var.gpu_pci_device_id != "" ? [var.gpu_pci_device_id] : []
  #   content {
  #     device_id = pci_device_id.value
  #   }
  # }

  # Cloud-init for initial setup
  extra_config = {
    "guestinfo.userdata" = base64encode(<<-EOF
      #cloud-config
      hostname: ${var.k3s_agent_name}
      users:
        - name: root
          ssh_authorized_keys:
            - ${var.ssh_public_key}
        - name: k3s
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
      package_update: true
      packages:
        - curl
        - wget
        - git
        - vim
        - htop
        - jq
        - build-essential
        - linux-headers-generic
      runcmd:
        - echo "K3s GPU Agent VM ready for deployment" > /var/log/vm-init.log
        - echo "Next: Install NVIDIA drivers and join K3s cluster" >> /var/log/vm-init.log
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
output "k3s_server_name" {
  description = "Name of the K3s server VM"
  value       = vsphere_virtual_machine.k3s_server.name
}

output "k3s_server_ip" {
  description = "IP address of the K3s server"
  value       = vsphere_virtual_machine.k3s_server.default_ip_address
}

output "k3s_agent_name" {
  description = "Name of the K3s GPU agent VM"
  value       = vsphere_virtual_machine.k3s_gpu_agent.name
}

output "k3s_agent_ip" {
  description = "IP address of the K3s GPU agent"
  value       = vsphere_virtual_machine.k3s_gpu_agent.default_ip_address
}

output "ssh_commands" {
  description = "SSH commands to connect to VMs"
  value       = <<-EOF

    # Connect to K3s Server
    ssh root@${vsphere_virtual_machine.k3s_server.default_ip_address}

    # Connect to K3s GPU Agent
    ssh root@${vsphere_virtual_machine.k3s_gpu_agent.default_ip_address}

  EOF
}

output "next_steps" {
  description = "Next steps after VM creation"
  value       = <<-EOF

    ============================================
    VMs Created Successfully!
    ============================================

    K3s Server:    ${vsphere_virtual_machine.k3s_server.name} (${vsphere_virtual_machine.k3s_server.default_ip_address})
    K3s GPU Agent: ${vsphere_virtual_machine.k3s_gpu_agent.name} (${vsphere_virtual_machine.k3s_gpu_agent.default_ip_address})

    Next Steps:
    -----------
    1. If using GPU passthrough, enable it in vSphere UI for ${vsphere_virtual_machine.k3s_gpu_agent.name}

    2. Update Ansible inventory:
       vim ../ansible/inventory/lab.yaml
       # Set k3s_server_ip and k3s_agent_ip

    3. Run the deployment:
       ../scripts/deploy-to-lab.sh

    Or manually install K3s:

    # On K3s Server:
    ssh root@${vsphere_virtual_machine.k3s_server.default_ip_address}
    curl -sfL https://get.k3s.io | sh -

    # Get the token:
    cat /var/lib/rancher/k3s/server/node-token

    # On K3s GPU Agent:
    ssh root@${vsphere_virtual_machine.k3s_gpu_agent.default_ip_address}
    curl -sfL https://get.k3s.io | K3S_URL=https://${vsphere_virtual_machine.k3s_server.default_ip_address}:6443 K3S_TOKEN=<token> sh -

  EOF
}

# =============================================================================
# Ansible Inventory Generation (optional)
# =============================================================================
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/generated-lab.yaml"
  content  = <<-EOF
# Auto-generated by Terraform - do not edit manually
# Generated: ${timestamp()}
all:
  vars:
    ansible_user: root
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    k3s_version: "v1.28.4+k3s1"
    gpu_time_slices: 4
    nvidia_driver_version: "535"

  children:
    k3s_servers:
      hosts:
        ${var.k3s_server_name}:
          ansible_host: ${vsphere_virtual_machine.k3s_server.default_ip_address}
          k3s_role: server

    k3s_agents:
      hosts:
        ${var.k3s_agent_name}:
          ansible_host: ${vsphere_virtual_machine.k3s_gpu_agent.default_ip_address}
          k3s_role: agent
          gpu_enabled: true
          gpu_type: "nvidia"
EOF

  depends_on = [
    vsphere_virtual_machine.k3s_server,
    vsphere_virtual_machine.k3s_gpu_agent
  ]
}
