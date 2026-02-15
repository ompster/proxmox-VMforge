terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  username = var.proxmox_user
  password = var.proxmox_password
  insecure = true
}

resource "proxmox_virtual_environment_vm" "win11" {
  name      = var.vm_name
  node_name = "pve"
  vm_id     = var.vm_id

  machine = "pc-q35-10.0"
  bios    = "ovmf"

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8096
  }

  # EFI disk with pre-enrolled Secure Boot keys (matches working VM)
  efi_disk {
    datastore_id    = "local-zfs"
    type            = "4m"
    pre_enrolled_keys = true
  }

  # TPM for Win11
  tpm_state {
    datastore_id = "local-zfs"
    version      = "v2.0"
  }

  # OS disk - SATA (not SCSI - matches working VM)
  disk {
    datastore_id = "local-zfs"
    interface    = "sata0"
    size         = 80
    file_format  = "raw"
  }

  # CD-ROM - Win11 ISO
  cdrom {
    file_id   = "local:iso/Win11_25H2_DEC25_MBUS.iso"
    interface = "ide2"
  }

  # NIC - e1000 (not virtio - matches working VM)
  network_device {
    bridge  = "vmbr0"
    model   = "e1000"
  }

  # VGA for Windows
  vga {
    type   = "std"
    memory = 64
  }

  operating_system {
    type = "win11"
  }

  # Boot order matching working VM
  boot_order = ["ide2", "sata0", "net0"]

  started = false
}
