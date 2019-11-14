variable "namespace" {
  type = string
  default = "default"
}

variable "storage_flavor" {
  type = string
  default = "mysql"
}

variable "storage_image" {
  type = string
  default = "mariadb:10.1.28"
}

variable "storage_class_name" {
  type = string
  default = "default"
}

variable "storage_size" {
  type = string
  default = "100Mi"
}

variable "server_port" {
  type = number
  default = 443
}

variable "server_trust_type" {
  type = string
  default = "remote"
}

variable "server_trust_hostname" {
  type = string
  default = "notary-signer"
}

variable "server_trust_port" {
  type = number
  default = 7899
}

variable "server_storage_db_url" {
  type = string
  default = "server:%% .Env.PASSWORD %%@tcp(notary-db:3306)/notaryserver"
}

variable "server_replicas" {
  type = number
  default = 3
}

variable "server_db_password" {
  type = string
  default = "password123"
}

variable "logging_level" {
  type = string
  default = "info"
}

variable "authentication_enabled" {
  type = bool
  default = false
}

variable "authentication_type" {
  type = string
  default = ""
}

variable "authentication_options" {
  type = map
  default = {}
}

variable "caching_enabled" {
  type = bool
  default = false
}

variable "caching_current_metadata" {
  type = number
  default = 300
}

variable "caching_consistent_metadata" {
  type = number
  default = 31536000
}

variable "gun_prefixes" {
  type = list(string)
  default = ["example.com"]
}

variable "signer_port" {
  type = number
  default = 7899
}

variable "signer_storage_db_url" {
  type = string
  default = "signer:%% .Env.PASSWORD %%@tcp(notary-db:3306)/notarysigner"
}

variable "signer_default_alias" {
  type = string
  default = "alias"
}

variable "signer_db_password" {
  type = string
  default = "password123"
}