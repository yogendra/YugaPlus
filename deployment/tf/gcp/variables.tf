
variable "app-name" {
  type        = string
  description = "Human Readable Application Name"
  default     = "YugabyteDB Samples - YugaPlus"
}
variable "app-machine-name" {
  type        = string
  description = "Machine readable application name used for urls, directory names, etc"
  default     = "YugaPlus"
}
variable "owner" {
  type        = string
  description = "Owner of the project"
}
variable "owner-email" {
  type        = string
  description = "Owner email"
}
variable "dept" {
  type        = string
  description = "Department who owns this deployment"
  default     = "sales"
}
variable "task" {
  type        = string
  description = "Purpose of the deployment"
  default     = "demo"
}
variable "expiry" {
  type        = string
  description = "When should this environment considered expired"
}
variable "github-repo" {
  type        = string
  description = "Github repository <username>/<repos> format. Used for sourcing script and code"
  default = "YugabyteDB-Samples/YugaPlus"
}
variable "git-branch" {
  type        = string
  description = "Git branch within the repository to deploy"
  default = "superbowl-demo"
}
variable "demo-script-url" {
  type = string
  description = "Demo script URL to download and put under /home/yugabyte/bin/demo in the nodes"
  default = "https://raw.githubusercontent.com/YugabyteDB-Sample/YugaPlus/main/deployment/demo"
}
variable "demo-script-boot-command" {
  type = string
  description = "Sub-command in boot script to run after installing OS setup"
  default = "boot"
}
variable "prefix" {
  type        = string
  description = "Prefix used in the resource name"
}

variable "yb-release" {
  type        = string
  description = "YugabyteDB Release (full) in the format 2.20.3.0-b1"
  default     = "2.20.3.0-b68"
}
variable "yb-arch" {
  type        = string
  description = "Deployment architecture. Only x86_64 tested"
  default     = "x86_64"
}
variable "allowed-web-client" {
  type        = list(string)
  description = "Allow list of IPs (CIDR Form) to access Web UIs (app, yugabtyed-ui, master, tserver)"
  default     = []
}
variable "allowed-admin-client" {
  type        = list(string)
  description = "Allow list of IPs (CIDR Form) full access  web, ssh, tcp, ping, etc"
  default     = []
}
variable "gcp-project" {
  type        = string
  description = "GCP Project to deploy into"
}
variable "gcp-image-family" {
  type        = string
  description = "OS image family to use for Vms. Only Ubuntu based images supported"
  default     = "ubuntu-2004-lts"
}
variable "gcp-image-project" {
  type        = string
  description = "OS image project to use for images. Only ubuntu-os-cloud tested"
  default     = "ubuntu-os-cloud"
}
variable "gcp-machine-type" {
  type        = string
  description = "GCP machine type to use for VMs"
  default     = "c2-standard-16"
}
variable "gcp-disk-type" {
  type        = string
  description = "GCP Disk type for VMs"
  default     = "pd-ssd"
}
variable "gcp-disk-size" {
  type        = string
  description = "Size of disk for VMs"
  default     = "50"
}
variable "gcp-cidr" {
  type        = string
  description = "GCP VPC Network CIDRs"
  default     = "10.99.0.0/16"
}
variable "gcp-dns-zone" {
  type        = string
  description = "GCP Hosted Zone"
  default = null
}
variable "gcp-regions" {
  type        = map(string)
  description = "GCP Region map. key is region name and value is human readable / City names"
  # validation {
  #   condition     = contains(["africa-south1", "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2", "australia-southeast1", "australia-southeast2", "europe-central2", "europe-north1", "europe-southwest1", "europe-west1", "europe-west10", "europe-west12", "europe-west2", "europe-west3", "europe-west4", "europe-west6", "europe-west8", "europe-west9", "me-central1", "me-central2", "me-west1", "northamerica-northeast1", "northamerica-northeast2", "southamerica-east1", "southamerica-west1", "us-central1", "us-east1", "us-east4", "us-east5", "us-south1", "us-west1", "us-west2", "us-west3", "us-west4"], keys(var.gcp-regions))
  #   error_message = "Valid values for gcp-region: run 'gcloud compute regions list --format=\"get(name)\"' "
  # }
}


variable "openai_api_key" {
  type        = string
  description = "Open AI API Key"
  sensitive   = true
}
