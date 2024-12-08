# Terraform Provider Block
provider "google" {
  credentials = file("../GCPKey.json")
  project     = var.gcp_project
  region      = var.gcp_region1
}

#Input Variables
# GCP Project
variable "gcp_project" {
  description = "Project in which GCP Resources to be created"
  type        = string
  default     = "ravi-project-442017-c0"
}

# GCP Region
variable "gcp_region1" {
  description = "Region in which GCP Resource to be created"
  type        = string
  default     = "us-central1"
}


# Infra starts here 

# Creating a Bucket
resource "google_storage_bucket" "website"{
    provider = google
    name = "${var.gcp_project}-bucket"
    location = "US"
}

# Upload the html file to the bucket
resource "google_storage_bucket_object" "static_site_src" {
    name = "index.html"
    source = "../website/index.html"
    bucket = google_storage_bucket.website.name
}

# Make the bucket object as public
resource "google_storage_object_access_control" "public_rule" {
    object = google_storage_bucket_object.static_site_src.output_name
    bucket = google_storage_bucket.website.name
    role = "READER"
    entity = "allUsers"
}

# # Make all the objects in the bucket as public
# resource "google_storage_default_object_access_control" "website_read" {
#     bucket = google_storage_bucket.website.name
#     role = "READER"
#     entity = "allUsers"
# }




# Reserve an external IP
resource "google_compute_global_address" "website" {
    provider = google
    name = "website-lb-ip"
}

# Get the managed DNS zone
data "google_dns_managed_zone" "gcp_coffeetime_dev"{
    provider = google
    name = "rishab-example"
}

# Add the IP to the DNS
resource "google_dns_record_set" "website" {
    provider = google
    name = "website.${data.google_dns_managed_zone.gcp_coffeetime_dev.dns_name}"
    type = "A"
    ttl = 300
    managed_zone = data.google_dns_managed_zone.gcp_coffeetime_dev.name
    rrdatas = [google_compute_global_address.website.address]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "website-backend" {
    provider = google
    name = "website-backend"
    description = "Contains files needed by the website"
    bucket_name = google_storage_bucket.website.name
    enable_cdn = true
}

# Create HTTPs certificate
resource "google_compute_managed_ssl_certificate" "website" {
    provider = google-beta
    name = "website-cert"
    managed {
      domains = [google_dns_record_set.website.name]
    }
}

# GCP URL Map
resource "google_compute_url_map" "website" {
    provider = google
    name = "website-url-map"
    default_service = google_compute_backend_bucket.website-backend.self_link
    host_rule {
        hosts = ["*"]
        path_matcher = "allpaths"
    }

    path_matcher {
      name = "allpaths"
      default_service = google_compute_backend_bucket.website-backend.self_link
    }
}

# GCP target proxy
resource "google_compute_target_https_proxy" "website" {
    provider = google
    name = "website-target-proxy"
    url_map = google_compute_url_map.website.self_link
    ssl_certificates = [google_compute_managed_ssl_certificate.website.self_link]
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
    provider = google
    name = "website-forwarding-rule"
    load_balancing_scheme = "EXTERNAL"
    ip_address = google_compute_global_address.website.address
    ip_protocol = "TCP"
    port_range = "443"
    target = google_compute_target_https_proxy.website.self_link
}