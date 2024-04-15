terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.24.0"
    }
  }
}



locals {
  allowed-admin-client = var.allowed-web-client
  allowed-web-client   = var.allowed-admin-client
  app-machine-name     = var.app-machine-name
  app-name             = var.app-name
  dept                 = var.dept
  expiry               = var.expiry
  gcp-cidr             = var.gcp-cidr
  gcp-disk-size        = var.gcp-disk-size
  gcp-disk-type        = var.gcp-disk-type
  gcp-dns-zone         = var.gcp-dns-zone
  gcp-image-family     = var.gcp-image-family
  gcp-image-project    = var.gcp-image-project
  gcp-machine-type     = var.gcp-machine-type
  gcp-network          = "${local.prefix}-vpc"
  gcp-project          = var.gcp-project
  gcp-regions          = var.gcp-regions
  git-branch           = var.git-branch
  github-repo          = var.github-repo
  openai_api_key       = var.openai_api_key
  owner                = var.owner
  owner-email          = var.owner-email
  prefix               = var.prefix
  task                 = var.task
  yb-arch              = var.yb-arch
  yb-release           = var.yb-release
  yb-version           = split("-", local.yb-release)[0]
  demo-script-url = var.demo-script-url
  demo-script-boot-command = var.demo-script-boot-command

  skip_dns = local.gcp-dns-zone == null || local.gcp-dns-zone == ""

  gcp-zones              = { for region, _ in local.gcp-regions : region => data.google_compute_zones.az[region].names[0] }
  zone-preference        = join(" ", [for index, region in keys(local.gcp-regions) : "gcp.${region}.${local.gcp-zones[region]}:${index + 1}"])
  gcp-region-subnet-cidr = { for index, region in keys(local.gcp-regions) : region => cidrsubnet(local.gcp-cidr, 4, index) }

  ssh-public-key = tls_private_key.private_key.public_key_openssh
  labels = {
    yb_task   = local.task
    yb_expire = local.expiry
    yb_owner  = local.owner
    yb_dept   = local.dept
  }
  node-private-ips-by-region = { for region, config in google_compute_address.private-ip : region => config.address }
  node-private-ips           = [for region, ip in local.node-private-ips-by-region : ip]
  node-public-ips            = [for region, config in google_compute_address.public-ip : config.address]
  my-ip                      = "${chomp(data.http.my-ip.response_body)}/32"
  admin-client-cidrs         = concat(local.allowed-admin-client, [local.gcp-cidr, local.my-ip])
  web-client-cidrs           = concat(local.allowed-web-client, local.admin-client-cidrs)

  demo-node-config = { for region, name in local.gcp-regions : region => <<EOT
export APP_NAME="${local.app-name}"
export APP_MACHINE_NAME="${local.app-machine-name}"
export REGION_NAME="${name}"
export REGION="${region}"
export ZONE="${local.gcp-zones[region]}"
export ZONE_PREFERENCE="${local.zone-preference}"
export OPENAI_API_KEY="${local.openai_api_key}"
export DB_URL="jdbc:yugabytedb://${local.node-private-ips-by-region[region]}:5433/yugabyte"
export DB_USER="yugabyte"
export DB_PASSWORD="yugabyte"
export DB_DRIVER_CLASS_NAME="com.yugabyte.Driver"
export BACKEND_API_KEY="superbowl-2024"
export PORT="8080"
export NODE_IP="${google_compute_address.private-ip[region].address}"
export YB_MASTERS="${join(",", formatlist("%s:7100", local.node-private-ips))}"
export YB_NODES=( ${join(" ", local.node-private-ips)} )
export YB_FIRST_NODE="${local.node-private-ips[0]}"
export YB_IS_PRIMARY="${google_compute_address.private-ip[region].address == local.node-private-ips[0] ? "TRUE" : "FALSE"}"
export YB_LOCATION="gcp.${region}.${local.gcp-zones[region]}"
export YB_VERSION="${local.yb-version}"
export YB_RELEASE="${local.yb-release}"
export YB_ARCH="${local.yb-arch}"
export GITHUB_REPO="${local.github-repo}"
export GIT_BRANCH="${local.git-branch}"
export REACT_APP_RUNTIME_ENVIRONMENT="docker"
export SPRING_FLYWAY_ENABLED="${local.node-private-ips[0] == google_compute_address.private-ip[region].address ? "true" : "false"}"
EOT
  }
}

provider "google" {
  alias = "boot"
}

data "google_client_config" "default" {
}

provider "google" {
  project        = local.gcp-project
  default_labels = local.labels
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
  source_ranges = local.web-client-cidrs
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
  source_ranges = local.admin-client-cidrs
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
  count = local.skip_dns?0:1
  name = local.gcp-dns-zone
}
locals {
  project-domain = local.skip_dns ? null : trimsuffix("${local.prefix}.${data.google_dns_managed_zone.dns[0].dns_name}", ".")
}


resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}


resource "local_sensitive_file" "ssh-private-key" {
  content         = tls_private_key.private_key.private_key_openssh
  file_permission = "0600"
  filename        = "${abspath(path.root)}/private/sshkey"
}

resource "local_sensitive_file" "ssh-public-key" {
  content         = tls_private_key.private_key.public_key_openssh
  file_permission = "0600"
  filename        = "${abspath(path.root)}/private/sshkey.pub"
}
resource "local_sensitive_file" "ssh-config" {
  content         = <<SSH_CONFIG
Host *
  IdentityFile ${local_sensitive_file.ssh-private-key.filename}
  User yugabyte
  UserKnownHostsFile /deb/null
  StrictHostKeyChecking no

%{~ for region, config in local.nodes ~}

Host ${region}, ${config.region-name}
  Hostname ${config.public.ip}

%{~ endfor ~}
SSH_CONFIG
  file_permission = "0600"
  filename        = "${abspath(path.root)}/private/ssh_config"
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
      ssh-key        = tls_private_key.private_key.private_key_openssh
      ssh-key-pub    = tls_private_key.private_key.public_key_openssh
      demo-env       = local.demo-node-config[each.key]
      github-repo    = local.github-repo
      git-branch     = local.git-branch
      demo-script-url = local.demo-script-url
      demo-script-boot-command = local.demo-script-boot-command
    })
    filename = "demo-machine.cloud-init.yaml"
  }
}
resource "google_compute_address" "public-ip" {
  for_each     = local.gcp-regions
  name         = "${local.prefix}-${each.key}"
  region       = each.key
  address_type = "EXTERNAL"
}
resource "google_compute_address" "private-ip" {
  for_each     = local.gcp-regions
  name         = "${local.prefix}-${each.key}-pvt"
  address_type = "INTERNAL"
  region       = each.key
  subnetwork   = google_compute_subnetwork.subnet[each.key].id

}

resource "google_dns_record_set" "public-fqdn" {
  for_each     = local.skip_dns ? {} : local.gcp-regions
  managed_zone = data.google_dns_managed_zone.dns[0].name
  name         = "${each.key}.${local.project-domain}."
  type         = "A"
  ttl          = 30
  rrdatas      = [google_compute_address.public-ip[each.key].address]
}


resource "google_dns_record_set" "private-fqdn" {
  for_each     = local.skip_dns ? {} : local.gcp-regions
  managed_zone = data.google_dns_managed_zone.dns[0].name
  name         = "${each.key}-pvt.${local.project-domain}."
  type         = "A"
  ttl          = 30
  rrdatas      = [google_compute_address.private-ip[each.key].address]
}

data "google_compute_zones" "az" {
  for_each = local.gcp-regions
  region   = each.key
}

resource "google_compute_instance" "vm" {
  for_each     = local.gcp-regions
  name         = local.nodes[each.key].name
  machine_type = local.gcp-machine-type
  zone         = local.nodes[each.key].zone
  hostname     = local.nodes[each.key].hostname

  boot_disk {
    initialize_params {
      image = data.google_compute_image.vm-image.id
      size  = local.gcp-disk-size
      type = local.gcp-disk-type
    }

  }

  network_interface {
    network = google_compute_network.vpc.name
    access_config {
      nat_ip = local.nodes[each.key].public.ip
    }
    network_ip = local.nodes[each.key].private.ip
    subnetwork = google_compute_subnetwork.subnet[each.key].id
  }
  metadata = {
    user-data = data.cloudinit_config.conf[each.key].rendered
  }
  labels                    = merge(local.labels, {})
  tags                      = ["demo-machine"]
  allow_stopping_for_update = true

}


locals {
  nodes = {
    for index, region in keys(local.gcp-regions) :
    region => {
      name       = "${local.prefix}-${region}"
      region-name = local.gcp-regions[region]
      preference = index + 1
      zone       = data.google_compute_zones.az[region].names[0]
      hostname   = local.skip_dns ? "${region}.local"  : trimsuffix(google_dns_record_set.public-fqdn[region].name, ".")
      private = {
        ip   = google_compute_address.private-ip[region].address
        fqdn = local.skip_dns ? "" : trimsuffix(google_dns_record_set.private-fqdn[region].name, ".")
      }
      public = {
        ip   = google_compute_address.public-ip[region].address
        fqdn = local.skip_dns ? "" : trimsuffix(google_dns_record_set.public-fqdn[region].name, ".")
      }
    }
  }
}

output "vms" {
  value = <<VMS
%{~ for region, config in local.nodes ~}

==> Region: ${region}(${local.gcp-regions[region]}) <==============

      VM: ${google_compute_instance.vm[region].name}
 Private: ${config.private.ip}
          %{~ if !local.skip_dns ~}
          ${config.private.fqdn}
          %{~ endif ~}
  Public: ${config.public.ip}
          %{~ if !local.skip_dns ~}
          ${config.public.fqdn}
          %{~ endif ~}
  YB Web: http://${config.public.ip}:15433/
          %{~ if !local.skip_dns ~}
          http://${config.public.fqdn}:15433/
          %{~ endif ~}
  Master: http://${config.public.ip}:7000/
          %{~ if !local.skip_dns ~}
          http://${config.public.fqdn}:7000/
          %{~ endif ~}
 Tserver: http://${config.public.ip}:9000/
          %{~ if !local.skip_dns ~}
          http://${config.public.fqdn}:9000/
          %{~ endif ~}
 App API: http://${config.public.ip}:8080/
          %{~ if !local.skip_dns ~}
          http://${config.public.fqdn}:8080
          %{~ endif ~}
  App UI: http://${config.public.ip}:3000/
          %{~ if !local.skip_dns ~}
          http://${config.public.fqdn}:3000
          %{~ endif ~}
     SSH: ssh -F ${local_sensitive_file.ssh-config.filename} ${config.region-name}
          ssh -F ${local_sensitive_file.ssh-config.filename} ${region}
          ssh -F ${local_sensitive_file.ssh-config.filename} ${config.public.ip}
          %{~ if !local.skip_dns ~}
          ssh -F ${local_sensitive_file.ssh-config.filename} ${config.public.fqdn}
          %{~ endif ~}
          gcloud compute ssh --zone ${config.zone} ${google_compute_instance.vm[region].name}
 Pvt SSH: ssh -i ~/.ssh/id_rsa  -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${config.private.ip}
          %{~ if !local.skip_dns ~}
          ssh -i ~/.ssh/id_rsa  -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" yugabyte@${config.private.fqdn}
          %{~ endif ~}

%{~ endfor ~}
VMS
}
