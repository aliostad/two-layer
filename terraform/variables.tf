variable "resource_group_name" {
  type        = string
  description = "Azure resource group name"
  default     = "rg-two-layer-demo"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "westeurope"
}

variable "app_service_plan_name" {
  type        = string
  description = "Shared App Service plan name"
  default     = "asp-two-layer-demo"
}

variable "layer1_app_name" {
  type        = string
  description = "Globally unique web app name for Layer1"
}

variable "layer2_app_name" {
  type        = string
  description = "Globally unique web app name for Layer2"
}

variable "acr_name" {
  type        = string
  description = "Azure Container Registry name (must be globally unique, alphanumeric only)"
}

variable "image_tag" {
  type        = string
  description = "Docker image tag to build and deploy"
  default     = "latest"
}

variable "tags" {
  type        = map(string)
  description = "Optional tags"
  default = {
    project = "two-layer"
  }
}
