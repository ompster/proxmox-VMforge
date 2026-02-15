variable "proxmox_url" {
  description = "Proxmox API endpoint"
  type        = string
  default     = "https://192.168.1.210:8006"
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "Name for the VM"
  type        = string
  default     = "Win11-Test"
}

variable "vm_id" {
  description = "VM ID in Proxmox"
  type        = number
  default     = 200
}
