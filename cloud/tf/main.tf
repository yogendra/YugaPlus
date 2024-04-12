terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.24.0"
    }
    acme = {
      source = "vancluever/acme"
    }
  }
}

variable "openai_api_key" {
  type = string
  description = "Open AI API Key"
  sensitive = true
}
locals {
  owner       = "yrampuria"
  owner-email = "yrampuria@yugabyte.com"
  dept        = "sales"
  task        = "webinar"
  expiry      = "2024-04-17_00-00-00_0000"

  prefix     = "apjsb"
  yb-version = "2.20.3.0"
  yb-release = "2.20.3.0-b68"
  yb-arch    = "x86_64"
  openai_api_key = var.openai_api_key
  gcp-project       = "apj-partner-enablement"
  gcp-network       = "${local.prefix}-vpc"
  gcp-image-family  = "ubuntu-2004-lts"
  gcp-image-project = "ubuntu-os-cloud"
  gcp-machine-type = "c2-standard-16"
  gcp-disk-type  ="pd-ssd"
  gcp-disk-size = "50"
  gcp-disk-iops = "3000"
  gcp-regions = {
    "asia-southeast1" = "Singapore"
    "asia-south1"     = "Mumbai"
    "asia-northeast1" = "Tokyo"
  }
  gcp-cidr               = "10.99.0.0/16"
  gcp-dns-zone           = "ws-apj-yugabyte-com"

  gcp-zones =  { for region, _ in local.gcp-regions: region =>  data.google_compute_zones.az[region].names[0]}
  zone-preference = join(",", [ for index, region in keys(local.gcp-regions): "gcp.${region}.${local.gcp-zones[region]}:${index}"])
  gcp-region-subnet-cidr = { for index, region in keys(local.gcp-regions) : region => cidrsubnet(local.gcp-cidr, 4, index) }

  ssh-public-key = tls_private_key.private_key.public_key_openssh
  labels = {
    yb_task   = local.task
    yb_expire = local.expiry
    yb_owner  = local.owner
    yb_dept   = local.dept
  }
  node-private-ips-by-region = { for region, config in google_compute_address.private-ip : region => config.address }
  node-private-ips = [ for region, ip in local.node-private-ips-by-region : ip ]
  node-public-ips = [ for region, config in google_compute_address.public-ip : config.address ]
  demo-node-config = { for region, name in local.gcp-regions: region => {
    REGION_NAME = name
    REGION = region
    ZONE = local.gcp-zones[region]
    ZONE_PREFERENCE = local.zone-preference
    OPEN_API_KEY = local.openai_api_key
    DB_URL = "jdbc:yugabytedb://${local.node-private-ips-by-region[region]}:5433/yugabyte"
    DB_USER = "yugabyte"
    DB_PASSWORD = "yugabyte"
    DB_DRIVER_CLASS = "com.yugabyte.Driver"
    BACKEND_API_KEY= "superbowl-2024"
    PORT = "8080"
    NODE_IP = google_compute_address.private-ip[region].address
    YB_MASTERS = join(",", formatlist("%s:7100",local.node-private-ips))
    YB_FIRST_NODE = local.node-private-ips[0]
    YB_LOCATION="gcp.${region}.${local.gcp-zones[region]}"
    YB_VERSION=local.yb-version
    YB_RELEASE=local.yb-release
    YB_ARCH=local.yb-arch
  }}
}
provider "google" {
  project        = local.gcp-project
  default_labels = local.labels
}


resource "google_service_account" "sa" {
  account_id   = "${local.prefix}-vm-sa"
  display_name = "${local.prefix} Custom SA for VM Instance"
}


resource "google_compute_network" "vpc" {
  name                    = local.gcp-network
  auto_create_subnetworks = false
  mtu                     = 1460
  routing_mode            = "GLOBAL"
}
resource "google_compute_subnetwork" "subnet" {
  for_each                 = local.gcp-regions
  description              = "${local.prefix} ${each.key} (${each.value}) subnet "
  name                     = "${local.prefix}-${each.key}"
  ip_cidr_range            = local.gcp-region-subnet-cidr[each.key]
  region                   = each.key
  private_ip_google_access = true
  network                  = google_compute_network.vpc.id

}

resource "google_compute_firewall" "public" {
  name    = "${local.prefix}-allow-public"
  network = google_compute_network.vpc.id
  allow {
    ports    = ["80", "443", "8080", "8443", "3000", "5000", "7000", "9000", "15433"]
    protocol = "tcp"
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["demo-machine"]
}

resource "google_compute_firewall" "gcpssh" {
  name    = "${local.prefix}-allow-gcpssh"
  network = google_compute_network.vpc.id
  allow {
    ports    = ["22"]
    protocol = "tcp"
  }
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["demo-machine"]
}

resource "google_compute_firewall" "private" {
  name    = "${local.prefix}-allow-private"
  network = google_compute_network.vpc.id
  allow {
    protocol = "all"
  }
  source_ranges = [local.gcp-cidr, "${chomp(data.http.my-ip.response_body)}/32"]
  target_tags   = ["demo-machine"]
}

data "google_compute_image" "vm-image" {
  family  = local.gcp-image-family
  project = local.gcp-image-project
}
data "http" "my-ip" {
  url = "https://ifconfig.me"
}

data "google_dns_managed_zone" "dns" {
  name = local.gcp-dns-zone
}
locals {
  project-domain = trimsuffix("${local.prefix}.${data.google_dns_managed_zone.dns.dns_name}", ".")
}

provider "acme" {
  server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"
  #server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "registration" {
  account_key_pem = tls_private_key.private_key.private_key_pem
  email_address   = local.owner-email # TODO put your own email in here!
}

resource "acme_certificate" "certificate" {
  account_key_pem           = acme_registration.registration.account_key_pem
  common_name               = local.project-domain
  subject_alternative_names = ["*.${local.project-domain}"]

  dns_challenge {
    provider = "gcloud"

    config = {
      GCE_PROJECT = local.gcp-project
      GCE_ZONE_ID = local.gcp-dns-zone
    }
  }
  depends_on = [acme_registration.registration]
}
resource "local_sensitive_file" "ssh-private-key" {
  content         = tls_private_key.private_key.private_key_openssh
  file_permission = "0600"
  filename        = "${path.module}/private/sshkey"
}

resource "local_sensitive_file" "ssh-public-key" {
  content         = tls_private_key.private_key.public_key_openssh
  file_permission = "0600"
  filename        = "${path.module}/private/sshkey.pub"
}


resource "local_sensitive_file" "cert-pem" {
  content         = acme_certificate.certificate.certificate_pem
  file_permission = "0600"
  filename        = "${path.module}/private/server-cert.pem"
}

resource "local_sensitive_file" "cert-p12" {
  content_base64  = acme_certificate.certificate.certificate_p12
  file_permission = "0600"
  filename        = "${path.module}/private/server-cert.p12"
}

resource "local_sensitive_file" "key-pem" {
  content         = acme_certificate.certificate.private_key_pem
  file_permission = "0600"
  filename        = "${path.module}/private/server-key.pem"
}

data "cloudinit_config" "conf" {
  for_each = local.gcp-regions

  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = templatefile("./templates/demo-machine.cloud-init.yaml", {
      yb-version     = local.yb-version
      yb-release     = local.yb-release
      yb-arch        = local.yb-arch
      ssh-public-key = local.ssh-public-key
      region-name    = each.value
      tls-key     = acme_certificate.certificate.private_key_pem
      tls-cert    = acme_certificate.certificate.certificate_pem
      tls-p12     = acme_certificate.certificate.certificate_p12
      demo-script = file("./templates/demo.sh")
      node-config = local.demo-node-config[each.key]
    })
    filename = "demo-machine.cloud-init.yaml"
  }
}
resource "google_compute_address" "public-ip" {
  for_each = local.gcp-regions
  name = "${local.prefix}-${each.key}"
  region = each.key
  address_type = "EXTERNAL"
}
resource "google_compute_address" "private-ip" {
  for_each = local.gcp-regions
  name = "${local.prefix}-${each.key}-pvt"
  address_type = "INTERNAL"
  region = each.key
  subnetwork = google_compute_subnetwork.subnet[each.key].id

}

resource "google_dns_record_set" "public-fqdn" {
  for_each = local.gcp-regions
  managed_zone = data.google_dns_managed_zone.dns.name
  name = "${each.key}.${local.project-domain}."
  type = "A"
  ttl = 30
  rrdatas = [google_compute_address.public-ip[each.key].address]
}


resource "google_dns_record_set" "private-fqdn" {
  for_each = local.gcp-regions
  managed_zone = data.google_dns_managed_zone.dns.name
  name = "${each.key}-pvt.${local.project-domain}."
  type = "A"
  ttl = 30
  rrdatas = [google_compute_address.private-ip[each.key].address]
}

data "google_compute_zones" "az" {
  for_each = local.gcp-regions
  region = each.key
}

resource "google_compute_instance" "vm" {
  for_each = local.gcp-regions
  name         = "${local.prefix}-${each.key}"
  machine_type = local.gcp-machine-type
  zone         = data.google_compute_zones.az[each.key].names[0]
  hostname = "${each.key}.${local.project-domain}"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.vm-image.id
      size = local.gcp-disk-size
      # provisioned_iops = local.gcp-disk-iops
      type = local.gcp-disk-type
    }

  }

  network_interface {
    network = google_compute_network.vpc.name
    access_config {
      nat_ip = google_compute_address.public-ip[each.key].address
    }
    network_ip = google_compute_address.private-ip[each.key].address
    subnetwork = google_compute_subnetwork.subnet[each.key].id
  }
  metadata = {
    user-data = data.cloudinit_config.conf[each.key].rendered
  }
  labels = merge(local.labels,{})
  tags = [ "demo-machine"]
   allow_stopping_for_update = true

}


output "vms" {
  value = <<VMS
%{ for region, name in local.gcp-regions ~}
==> Region: ${region}(${name}) <==============
      VM: ${google_compute_instance.vm[region].name}
 Private: ${google_compute_address.private-ip[region].address}
          ${google_dns_record_set.private-fqdn[region].name}
  Public: ${google_compute_address.public-ip[region].address}
          ${google_dns_record_set.public-fqdn[region].name}
  YB Web: http://${google_compute_address.public-ip[region].address}:15433/
          http://${google_dns_record_set.public-fqdn[region].name}:15433/
  Master: http://${google_compute_address.public-ip[region].address}:7000/
          http://${google_dns_record_set.public-fqdn[region].name}:7000/
 Tserver: http://${google_compute_address.public-ip[region].address}:9000/
          http://${google_dns_record_set.public-fqdn[region].name}:9000/
     App: http://${google_compute_address.public-ip[region].address}:8080/
          http://${google_dns_record_set.public-fqdn[region].name}:8080
     SSH: ssh -i ${local_sensitive_file.ssh-private-key.filename} -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${google_compute_address.public-ip[region].address}
          ssh -i ${local_sensitive_file.ssh-private-key.filename} -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${google_dns_record_set.public-fqdn[region].name}
          gcloud compute ssh --zone ${google_compute_instance.vm[region].zone} ${google_compute_instance.vm[region].name}
%{ endfor ~}
VMS
}
