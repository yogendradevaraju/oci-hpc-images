/* variables */

packer {
    required_plugins {
      oracle = {
        source = "github.com/hashicorp/oracle"
        version = ">= 1.0.3"
      }
    ansible = {
      version = "~> 1"
      source = "github.com/hashicorp/ansible"
    }
    }
}

variable "image_base_name" {
  type    = string
  default = "Canonical-Ubuntu-24.04-2024.10.09-0-OCA-DOCA-OFED-2.10.0-GPU-570-CUDA-12.8-2025-02-25.0"
}

variable "image_id" {
  type    = string
  default = "ocid1.image.oc1.ca-montreal-1.aaaaaaaa55qfo5n4z56tfer32xzqqbep7axi34mk5hxqkttakanyilpimkwq"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "build_options" {
  type    = string
  default = "noselinux,nomitigations,openmpi,nvidia,enroot,monitoring,benchmarks,networkdevicenames,use_plugins"
}

variable "build_groups" {
  default = [ "kernel_parameters", "oci_hpc_packages", "mofed_doca_2100", "hpcx_2221", "openmpi_414", "nvidia_570", "nvidia_cuda_12_8" , "use_plugins" , "oca_149"]
}

/* authentication variables, edit and use defaults.pkr.hcl instead */

variable "region" { type = string }
variable "ad" { type = string }
variable "compartment_ocid" { type = string }
variable "shape" { type = string }
variable "subnet_ocid" { type = string }
variable "use_instance_principals" { type = bool }
variable "access_cfg_file_account" {
  type = string
  default = "DEFAULT"
}

variable "access_cfg_file" {
  type = string
  default = "~/.oci/config"
}

/* changes should not be required below */

source "oracle-oci" "oracle" {
  availability_domain = var.ad
  base_image_ocid     = var.image_id
  compartment_ocid    = var.compartment_ocid
  image_name          = local.build_name
  shape               = var.shape
  shape_config        { ocpus = "16" }
  ssh_username        = var.ssh_username
  subnet_ocid         = var.subnet_ocid
  access_cfg_file     = var.use_instance_principals ? null : var.access_cfg_file
  access_cfg_file_account = var.use_instance_principals ? null : var.access_cfg_file_account
  region              = var.use_instance_principals ? null : var.region
  user_data_file      = "${path.root}/../files/user_data.txt"
  disk_size           = 60
  use_instance_principals = var.use_instance_principals
  ssh_timeout         = "90m"
  instance_name       = "HPC-ImageBuilder-${local.build_name}"
}

locals {
  ansible_args        = "options=[${var.build_options}]"
  ansible_groups      = "${var.build_groups}"
  build_name          = "${var.image_base_name}"
}

build {
  name    = "buildname"
  sources = ["source.oracle-oci.oracle"]

  provisioner "shell" {
    inline = ["sudo growpart /dev/sda 1"]
    valid_exit_codes = [0, 1] // 1 is returned if the partition is already the size of the disk
  }

  provisioner "shell" {
    inline = ["sudo resize2fs /dev/sda1"]
    valid_exit_codes = [0, 1]
  }

  provisioner "ansible" {
    playbook_file   = "${path.root}/../../ansible/hpc.yml"
    extra_arguments = ["-e", local.ansible_args]
    groups = local.ansible_groups
    user = var.ssh_username
  }

  provisioner "shell" {
    inline = ["rm -rf $HOME/~*", "sudo /usr/libexec/oci-image-cleanup --force"]
  }
}