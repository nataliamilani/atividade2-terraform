# Aluno: Natalia Fernanda Milani de Moraes
# RA   : 2100121
# Curso: MBA Full Stack Developer

# ssh azureuser@<ip_public>
# mysql -u teste -p

terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

#CRIAR RESOURCE GROUP
resource "azurerm_resource_group" "rg_aula_terraform" {
    name     = "rg_aula_terraform"
    location = "eastus"
}

#CRIAR VIRTUAL NETWORK
resource "azurerm_virtual_network" "vn_aula_terraform" {
    name                = "vn_aula_terraform"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rg_aula_terraform.name
}

#CRIAR SUBNET
resource "azurerm_subnet" "subnet_aula_terraform" {
    name                 = "subnet_aula_terraform"
    resource_group_name  = azurerm_resource_group.rg_aula_terraform.name
    virtual_network_name = azurerm_virtual_network.vn_aula_terraform.name
    address_prefixes       = ["10.0.1.0/24"]
}

#CRIAR IP PUBLICO
resource "azurerm_public_ip" "publicip_aula_terraform" {
    name                         = "publicip_aula_terraform"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.rg_aula_terraform.name
    allocation_method            = "Static"
}

#CRIAR NETWORK SECURITY GROUP - LIBERANDO AS PORTAS 3306 E 22
resource "azurerm_network_security_group" "nsg_aula_terraform" {
    name                = "nsg_aula_terraform"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rg_aula_terraform.name

    security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

#CRIAR NETWORK INTERFACE E CONFIGURACOES DE IP
resource "azurerm_network_interface" "nic_aula_terraform" {
    name                      = "nic_aula_terraform"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.rg_aula_terraform.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.subnet_aula_terraform.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.publicip_aula_terraform.id
    }
}


resource "azurerm_network_interface_security_group_association" "nisga_aula_terraform" {
    network_interface_id      = azurerm_network_interface.nic_aula_terraform.id
    network_security_group_id = azurerm_network_security_group.nsg_aula_terraform.id
}

data "azurerm_public_ip" "ip_data_db" {
  name                = azurerm_public_ip.publicip_aula_terraform.name
  resource_group_name = azurerm_resource_group.rg_aula_terraform.name
}

resource "azurerm_storage_account" "saaulaterraform" {
    name                        = "saaulaterraform"
    resource_group_name         = azurerm_resource_group.rg_aula_terraform.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

#CRIANDO MAQUINA VIRTUAL
resource "azurerm_linux_virtual_machine" "vm_aula_terraform" {
    name                  = "vm_aula_terraform"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.rg_aula_terraform.name
    network_interface_ids = [azurerm_network_interface.nic_aula_terraform.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDiskMySQL"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "myvm"
    admin_username = var.user
    admin_password = var.password
    disable_password_authentication = false

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.saaulaterraform.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.rg_aula_terraform ]
}

#IMPRIMINDO NO TERMINAL O IP PUBLICO
output "public_ip_address_mysql" {
  value = azurerm_public_ip.publicip_aula_terraform.ip_address
}


resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vm_aula_terraform]
  create_duration = "30s"
}

#UPLOAD DA PASTA CONFIG
resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        source = "config"
        destination = "/home/azureuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

#INSTALACAO DO MYSQL
resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/azureuser/config/user.sql",
            "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}