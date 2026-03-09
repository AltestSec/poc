# Windows VM for accessing private network
# Cheapest configuration for desktop access and ACR operations

# Public IP for RDP access
resource "azurerm_public_ip" "vm" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Network Interface
resource "azurerm_network_interface" "vm" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = var.tags
}

# Network Security Group for RDP
resource "azurerm_network_security_group" "vm" {
  name                = "${var.name}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Allow RDP from your IP only
  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_rdp_source_ip
    destination_address_prefix = "*"
  }

  # Allow outbound to internet
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = var.tags
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# Windows VM - Cheapest SKU
resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 127
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-23h2-pro"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  tags = var.tags
}

# VM Extension to install Docker and Azure CLI
resource "azurerm_virtual_machine_extension" "setup" {
  name                       = "SetupTools"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = <<-EOT
      powershell -ExecutionPolicy Unrestricted -Command "
        # Install Chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force;
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));
        
        # Install Docker Desktop
        choco install docker-desktop -y;
        
        # Install Azure CLI
        choco install azure-cli -y;
        
        # Install Git
        choco install git -y;
        
        # Create desktop shortcuts
        $WshShell = New-Object -comObject WScript.Shell;
        $Shortcut = $WshShell.CreateShortcut('C:\\Users\\Public\\Desktop\\Azure CLI.lnk');
        $Shortcut.TargetPath = 'C:\\Program Files\\Microsoft SDKs\\Azure\\CLI2\\wbin\\az.cmd';
        $Shortcut.Save();
        
        # Create readme on desktop
        @'
        Welcome to Airflow Build VM
        
        This VM is configured to access your private Azure Container Registry.
        
        Quick Start:
        1. Open PowerShell as Administrator
        2. Login to Azure: az login
        3. Login to ACR: az acr login --name <your-acr-name>
        4. Build images: docker build -t <acr>.azurecr.io/airflow:latest .
        5. Push images: docker push <acr>.azurecr.io/airflow:latest
        
        The VM has:
        - Docker Desktop
        - Azure CLI
        - Git
        - Managed Identity for ACR access
        
        Note: You may need to restart after first login for Docker to work.
'@ | Out-File -FilePath 'C:\\Users\\Public\\Desktop\\README.txt' -Encoding UTF8;
      "
    EOT
  })

  tags = var.tags
}
