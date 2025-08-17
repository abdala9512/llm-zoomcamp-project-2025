variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ocr-service-llm-zoomcamp"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "input_bucket" {
  type    = string
  default = null
}

variable "output_bucket" {
  type    = string
  default = null
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "timeout_s" {
  type    = number
  default = 120
}

variable "ephemeral_mb" {
  type    = number
  default = 2048
}

variable "prefix" {
  type    = string
  default = "docs/"
}

variable "suffix" {
  type    = string
  default = ".pdf"
}

variable "enable_ocr" {
  type    = string
  default = "auto"

  validation {
    condition     = contains(["auto", "always", "never"], var.enable_ocr)
    error_message = "enable_ocr must be one of: auto, always, or never."
  }
}
