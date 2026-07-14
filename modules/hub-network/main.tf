###############################################################################
# Module: hub-network
# Step 5 of the Landing Zone blueprint - Hub VNet (shared connectivity)
#   - Hub VNet with GatewaySubnet, AzureFirewallSubnet, AzureBastionSubnet
#   - Azure Firewall + baseline policy
#   - VPN Gateway (optional)
#   - Azure Bastion (optional)
#   - Private DNS zones (optional)
###############################################################################

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.prefix}-hub-${var.environment}-${var.location_short}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.prefix}-hub-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.hub_address_space]
  dns_servers         = var.dns_servers
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Subnets (Azure reserved names required for firewall/gateway/bastion)
# ---------------------------------------------------------------------------
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 0)] # /26 from /24
}

resource "azurerm_subnet" "gateway" {
  count                = var.deploy_vpn_gateway ? 1 : 0
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 1)]
}

resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 2)]
}

resource "azurerm_subnet" "shared_services" {
  name                 = "snet-shared-services"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 3)]
}

# ---------------------------------------------------------------------------
# Azure Firewall + policy
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "firewall" {
  name                = "pip-afw-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                = "afwp-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = var.firewall_sku_tier

  dns {
    proxy_enabled = true
  }

  tags = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "baseline" {
  name               = "rcg-baseline"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  network_rule_collection {
    name     = "allow-spoke-to-spoke"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "spoke-to-spoke-any"
      protocols             = ["Any"]
      source_addresses      = var.spoke_address_spaces
      destination_addresses = var.spoke_address_spaces
      destination_ports     = ["*"]
    }
  }

  application_rule_collection {
    name     = "allow-platform-fqdns"
    priority = 200
    action   = "Allow"

    rule {
      name = "azure-and-ubuntu-updates"
      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }
      source_addresses = var.spoke_address_spaces
      destination_fqdns = [
        "*.azure.com",
        "*.microsoft.com",
        "*.windowsupdate.com",
        "*.ubuntu.com",
        "*.docker.io",
        "*.docker.com",
        "ghcr.io",
        "*.githubusercontent.com",
      ]
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = "afw-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this.id

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# VPN Gateway (optional - long deploy time ~30-45 min)
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "vpn" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = "pip-vpngw-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = "vpngw-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_gateway_sku
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vpngw-ipconfig"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Bastion (optional)
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "pip-bas-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "bas-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "Basic"

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Private DNS zones (Step 4/5 - DNS shared service)
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "zones" {
  for_each            = toset(var.private_dns_zones)
  name                = each.value
  resource_group_name = azurerm_resource_group.hub.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = azurerm_private_dns_zone.zones
  name                  = "link-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
}

# ---------------------------------------------------------------------------
# Firewall diagnostics -> central Log Analytics
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "diag-afw"
  target_resource_id         = azurerm_firewall.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
