locals {
  # Full image references for build/push operations.
  layer1_image_full = "${azurerm_container_registry.this.login_server}/layer1-batchapi:${var.image_tag}"
  layer2_image_full = "${azurerm_container_registry.this.login_server}/layer2-simulator:${var.image_tag}"

  # App Service expects repository:tag here, not a fully-qualified registry URL.
  layer1_image_name = "layer1-batchapi:${var.image_tag}"
  layer2_image_name = "layer2-simulator:${var.image_tag}"
  repo_root    = "${path.module}/.."
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = var.tags
}

# Build and push Layer 2 image into ACR from local source.
resource "null_resource" "push_layer2" {
  triggers = {
    dockerfile = filemd5("${local.repo_root}/Layer2.Simulator/Dockerfile")
    csproj     = filemd5("${local.repo_root}/Layer2.Simulator/Layer2.Simulator.csproj")
    program    = filemd5("${local.repo_root}/Layer2.Simulator/Program.cs")
    image_tag  = var.image_tag
    platform   = "linux-amd64"
    builder    = "local-docker"
    auth_mode  = "docker-config-auth"
  }

  provisioner "local-exec" {
    working_dir = local.repo_root
    command     = <<-EOT
      export DOCKER_CONFIG="/tmp/two-layer-docker" && \
      mkdir -p "$DOCKER_CONFIG" && \
      AUTH=$(printf "%s:%s" "${azurerm_container_registry.this.admin_username}" "${azurerm_container_registry.this.admin_password}" | base64 | tr -d '\n') && \
      printf '{"auths":{"%s":{"auth":"%s"}}}\n' "${azurerm_container_registry.this.login_server}" "$AUTH" > "$DOCKER_CONFIG/config.json" && \
      docker --config "$DOCKER_CONFIG" build --platform linux/amd64 -f Layer2.Simulator/Dockerfile -t ${local.layer2_image_full} . && \
      docker --config "$DOCKER_CONFIG" push ${local.layer2_image_full}
    EOT
  }

  depends_on = [azurerm_container_registry.this]
}

# Build and push Layer 1 image into ACR from local source.
resource "null_resource" "push_layer1" {
  triggers = {
    dockerfile = filemd5("${local.repo_root}/Layer1.BatchApi/Dockerfile")
    csproj     = filemd5("${local.repo_root}/Layer1.BatchApi/Layer1.BatchApi.csproj")
    program    = filemd5("${local.repo_root}/Layer1.BatchApi/Program.cs")
    image_tag  = var.image_tag
    platform   = "linux-amd64"
    builder    = "local-docker"
    auth_mode  = "docker-config-auth"
  }

  provisioner "local-exec" {
    working_dir = local.repo_root
    command     = <<-EOT
      export DOCKER_CONFIG="/tmp/two-layer-docker" && \
      mkdir -p "$DOCKER_CONFIG" && \
      AUTH=$(printf "%s:%s" "${azurerm_container_registry.this.admin_username}" "${azurerm_container_registry.this.admin_password}" | base64 | tr -d '\n') && \
      printf '{"auths":{"%s":{"auth":"%s"}}}\n' "${azurerm_container_registry.this.login_server}" "$AUTH" > "$DOCKER_CONFIG/config.json" && \
      docker --config "$DOCKER_CONFIG" build --platform linux/amd64 -f Layer1.BatchApi/Dockerfile -t ${local.layer1_image_full} . && \
      docker --config "$DOCKER_CONFIG" push ${local.layer1_image_full}
    EOT
  }

  depends_on = [azurerm_container_registry.this]
}

resource "azurerm_service_plan" "this" {
  name                = var.app_service_plan_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

resource "azurerm_linux_web_app" "layer2" {
  name                = var.layer2_app_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true

  site_config {
    application_stack {
      docker_image_name        = local.layer2_image_name
      docker_registry_url      = "https://${azurerm_container_registry.this.login_server}"
      docker_registry_username = azurerm_container_registry.this.admin_username
      docker_registry_password = azurerm_container_registry.this.admin_password
    }
  }

  app_settings = {
    ASPNETCORE_ENVIRONMENT = "Production"
    ASPNETCORE_URLS        = "http://+:8080"
    WEBSITES_PORT          = "8080"
  }

  tags       = var.tags
  depends_on = [null_resource.push_layer2]
}

resource "azurerm_linux_web_app" "layer1" {
  name                = var.layer1_app_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true

  site_config {
    application_stack {
      docker_image_name        = local.layer1_image_name
      docker_registry_url      = "https://${azurerm_container_registry.this.login_server}"
      docker_registry_username = azurerm_container_registry.this.admin_username
      docker_registry_password = azurerm_container_registry.this.admin_password
    }
  }

  app_settings = {
    ASPNETCORE_ENVIRONMENT = "Production"
    ASPNETCORE_URLS        = "http://+:8080"
    WEBSITES_PORT          = "8080"
    Layer2__BaseUrl        = "https://${azurerm_linux_web_app.layer2.default_hostname}"
  }

  tags       = var.tags
  depends_on = [null_resource.push_layer1]
}
