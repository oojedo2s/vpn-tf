resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_subnetwork" "mysubnet" {
  name = "mysubnet"
  ip_cidr_range = "10.0.20.0/24"
  region = var.region
  network = google_compute_network.vpc_network.self_link
}

resource "google_compute_firewall" "allow-iap-traffic" {
  allow {
    ports    = [1194]
    protocol = "udp"
  }

  allow {
    ports = [22, 80]
    protocol = "tcp"
  }
  
  description = "Allows TCP connections from IAP to any instance on the network using port 22."
  direction   = "INGRESS"
  disabled    = false
  name        = "allow-iap-traffic"
  network     = google_compute_network.vpc_network.self_link
  priority    = 1000
  source_ranges = [
    // Since we have private IP's for our GKE nodes we need to use Google IAP to access them
    // We need to allow this specific range to have access
    "35.235.240.0/20" // Cloud IAP's TCP netblock see https://cloud.google.com/iap/docs/using-tcp-forwarding
  ]
}

resource "google_compute_instance" "default" {
  for_each     = toset(var.name_count)
  name         = each.key
  machine_type = var.machine_type
  #machine_type = var.machine_type_1 == "n1-standard-1" ? var.machine_type_1 : var.machine_type_4
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mysubnet.self_link
    network_ip = google_compute_instance.default.name == "caserver" ? "10.0.20.10" : "10.0.20.20"
  }

provisioner "file" {
  source =  google_compute_instance.default.name == "caserver" ? "./cascr" : "./vpnscr"
  destination = "~/Documents"
}
}

output "instance_name" {
  value = [for inst in google_compute_instance.default : inst.name]
}
output "machine_type" {
  value = [for inst in google_compute_instance.default : inst.machine_type]
}

output "network_ip" {
  value = [for inst in google_compute_instance.default : inst.network_interface.0.network_ip]
}