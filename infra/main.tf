terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  # No remote backend configured — state stays local since we're not applying
  # this for real yet. Add an azurerm backend block once you have live access again.
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-devsecops-hub"
  location = "uksouth"
}

resource "azurerm_container_registry" "hub" {
  name                = "devsecopshubacr001" # must be globally unique, alphanumeric only
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = "Basic"
  admin_enabled       = false # we use managed identity / OIDC, not admin creds
}

resource "azurerm_log_analytics_workspace" "hub" {
  name                = "law-devsecops-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "hub" {
  name                       = "cae-devsecops-hub"
  resource_group_name       = azurerm_resource_group.hub.name
  location                   = azurerm_resource_group.hub.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id
}

resource "azurerm_user_assigned_identity" "hub_identity" {
  name                = "id-devsecops-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.hub.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.hub_identity.principal_id
}

resource "azurerm_container_app" "hub" {
  name                         = "ca-devsecops-hub"
  container_app_environment_id = azurerm_container_app_environment.hub.id
  resource_group_name          = azurerm_resource_group.hub.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.hub_identity.id]
  }

  registry {
    server   = azurerm_container_registry.hub.login_server
    identity = azurerm_user_assigned_identity.hub_identity.id
  }

  template {
    container {
      name   = "hub"
      image  = "${azurerm_container_registry.hub.login_server}/devsecops-hub:initial"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port       = 8080
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# IaC flaw: storage account with three deliberate misconfigurations
resource "azurerm_storage_account" "hub" {
  name                     = "stdevsecops001"
  resource_group_name      = azurerm_resource_group.hub.name
  location                 = azurerm_resource_group.hub.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # IaC flaw 1: public blob access allowed (data exposed to the internet)
  allow_nested_items_to_be_public = true

  # IaC flaw 2: HTTPS-only disabled (traffic can travel in plain HTTP)
  enable_https_traffic_only = false

  # IaC flaw 3: outdated minimum TLS version (TLS 1.0 accepted)
  min_tls_version = "TLS1_0"
}

output "acr_login_server" {
  value = azurerm_container_registry.hub.login_server
}

output "app_url" {
  value = azurerm_container_app.hub.latest_revision_fqdn
}