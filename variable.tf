variable "project" {
  default = "prac-project-1"
}

variable "region" {
  default = "europe-west3"
}

variable "zone" {
  default = "europe-west3-c"
}

variable "image" {
  default = "ubuntu-os-cloud/ubuntu-2004-lts"
}

variable "machine_type" {
  default = "n1-standard-1"
}

variable "name_count" {
  default = ["caserver", "vpnserver"]
}
