###############################################################################
# Module: spoke-network
# Step 5 (spokes) + Step 8 (app onboarding network) of the blueprint
#   - Spoke VNet with workload subnets
#   - Bidirectional peering to hub
#   - UDR forcing egress via Azure Firewall
#   - NSG baseline on every subnet
#   - Private DNS zone links
###############################################################################

resource "azurerm_resource_group" "spoke" {
  name     = "rg-${var.prefix}-${var.workload}-${var.environment}-${var.location_short}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-${var.prefix}-${var.workload}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  address_space       = [var.spoke_address_space]
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "subnets" {
  for_each = var.subnets

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [each.value.cidr]
  service_endpoints    = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = "delegation"
      service_delegation {
        name = delegation.value
      }
    }
  }
}

# ---------------------------------------------------------------------------
# NSG baseline: deny inbound from internet, allow VNet + LB
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "baseline" {
  name                = "nsg-${var.prefix}-${var.workload}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name

  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetInBound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "baseline" {
  for_each = azurerm_subnet.subnets

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.baseline.id
}

# ---------------------------------------------------------------------------
# UDR: default route via hub Azure Firewall
# ---------------------------------------------------------------------------
resource "azurerm_route_table" "egress_via_firewall" {
  name                          = "rt-${var.prefix}-${var.workload}-${var.environment}-${var.location_short}"
  location                      = azurerm_resource_group.spoke.location
  resource_group_name           = azurerm_resource_group.spoke.name
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  tags = var.tags
}

resource "azurerm_subnet_route_table_association" "egress" {
  for_each = azurerm_subnet.subnets

  subnet_id      = each.value.id
  route_table_id = azurerm_route_table.egress_via_firewall.id
}

# ---------------------------------------------------------------------------
# Hub <-> Spoke peering
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${var.workload}-to-hub"
  resource_group_name          = azurerm_resource_group.spoke.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = var.use_hub_gateway
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-${var.workload}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = var.use_hub_gateway
}

# ---------------------------------------------------------------------------
# Link spoke VNet to central private DNS zones
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = var.private_dns_zone_names

  name                  = "link-${var.workload}"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = azurerm_virtual_network.spoke.id
}
