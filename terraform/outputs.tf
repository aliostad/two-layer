output "layer1_url" {
  description = "Layer1 Batch API URL"
  value       = "https://${azurerm_linux_web_app.layer1.default_hostname}"
}

output "layer2_url" {
  description = "Layer2 Simulator API URL"
  value       = "https://${azurerm_linux_web_app.layer2.default_hostname}"
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}
