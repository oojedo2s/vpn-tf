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
    ports    = [22]
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
  name         = var.instance_name
  machine_type = var.machine_type
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = var.image
      size = 40
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mysubnet.self_link
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