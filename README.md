# Proxmox Win11 VM Automation

> ⚠️ **WARNING:** This is for internal/lab testing only. Do NOT use in production environments.

Terraform + PowerShell automation for spinning up Windows 11 VMs on Proxmox. Zero-touch — creates the VM, boots from ISO, and sends keypresses to start the installer automatically.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- Proxmox VE with a Windows 11 ISO uploaded to `local` storage
- PowerShell 5.1+

## Setup

1. Clone this repo
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and set your Proxmox password
3. Update `variables.tf` with your Proxmox URL, ISO filename, etc.
4. Run `terraform init`

## Usage

```powershell
# Deploy a single VM
.\deploy.ps1

# Deploy multiple VMs
.\deploy.ps1 -Count 3

# Deploy with custom name
.\deploy.ps1 -Name "SOE-Test"

# List VMs in managed range
.\deploy.ps1 -List

# Destroy a specific VM
.\deploy.ps1 -Destroy 201

# Destroy all managed VMs
.\deploy.ps1 -DestroyAll
```

## Environment Variables

Instead of `terraform.tfvars`, you can use environment variables:

| Variable | Default | Description |
|---|---|---|
| `PVE_URL` | `https://192.168.1.210:8006` | Proxmox API endpoint |
| `PVE_USER` | `root@pam` | Proxmox username |
| `PVE_PASSWORD` | *(prompt)* | Proxmox password |
| `PVE_NODE` | `pve` | Proxmox node name |

## VM Specs

- **OS:** Windows 11 25H2
- **CPU:** 2 cores (x86-64-v2-AES)
- **RAM:** 8GB
- **Disk:** 80GB (SATA, ZFS)
- **NIC:** e1000, bridged (vmbr0)
- **UEFI:** OVMF with Secure Boot + TPM 2.0
- **VM ID range:** 200-299

## How It Works

1. Terraform creates the VM with UEFI, TPM, and ISO mounted
2. PowerShell starts the VM via Proxmox API
3. Spacebar is spammed via `sendkey` API to catch the "Press any key to boot from CD" prompt
4. Windows answer file (on the ISO) handles the rest of the install unattended
