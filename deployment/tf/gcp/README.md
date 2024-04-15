# GCP Deployment Guide

## Required
* terraform 1.3+
* gcloud cli
* editor (vi/code/nano/etc.)
* GCP Permission
  * Create/Update/Delete VPC
  * Create/Update/Delete Firewall Rule
  * Create/Update/Delete Compute Instances
  * Create/Update/Delete Disk
  * (Optional) Create/Update/Delete DNS RecordSet
* GCP Resource
  * (Optional) DNS Hosted Zone


# How to deploy to GCP

1. Connect to GCP via `gcloud`
2. Create variable file based on `terraform.tfvars.exanple`. Key required variables are:
   1. openai_api_key
   2. owner
   3. owner-email
   4. expiry
   5. gcp-project
   6. gcp-regions: Map of GCP region name and human friendly names
   7. prefix
   8. gcp-dns-zone
3. Run terraform

    ```bash
    terraform init
    terraform apply
    ```
4. In 10 minutes or so, you should see output like following

    ```log
    ==> Region: asia-northeast1(Tokyo) <==============

          VM: apjsb-asia-northeast1
    Private: 10.99.0.2
              asia-northeast1-pvt.apjsb.ws.apj.yugabyte.com
      Public: 35.187.218.169
              asia-northeast1.apjsb.ws.apj.yugabyte.com
      YB Web: http://35.187.218.169:15433/
              http://asia-northeast1.apjsb.ws.apj.yugabyte.com:15433/
      Master: http://35.187.218.169:7000/
              http://asia-northeast1.apjsb.ws.apj.yugabyte.co
    ...
    ...
    ```

