#
# Basic method wrapper.
#
function New-PsCluster{

<#
    .SYNOPSIS
    This file simply exports some wrapper methods to help with creation of a VMSS.
#>

    # Parameter definitions
    param(
        [parameter(Mandatory=$true)]
        [String]$Location,

        [parameter(Mandatory=$true)]
        [String]$ClusterName,

        [parameter(Mandatory=$true)]
        [String]$ResourceGroupName,

        [parameter(Mandatory=$true)]
        [Int]$ClusterSize
    )

    #
    # Log message function
    #
    function Write-Log($msg){
        $now = [DateTime]::Now
        Write-Host "[$now]: $msg"
    }

    #
    # The basics - create a resource group
    #
    Write-Log "Creating resource group"
    New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location

    #
    # We need a pool of storage accounts
    #
    Write-Log "Creating storage account pool"

    # TODO: Put this in a loop driven from a parameter
    New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name "11172016vmssa1" -SkuName Standard_LRS -Location $Location
    New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name "11172016vmssa2" -SkuName Standard_LRS -Location $Location
    New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name "11172016vmssa3" -SkuName Standard_LRS -Location $Location

    #
    # And a network / subnet profile
    #
    Write-Log "Creating VNET / subnet profile"
    $vnetName = "vnet1"
    $subnet1Name = "subnet1"
    $subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $subnet1Name -AddressPrefix 10.0.0.0/24 
    $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix 10.0.0.0/16 -Subnet $subnetConfig
    $ipConfig = New-AzureRmVmssIpConfig -Name "PsClusterIpConfig" -LoadBalancerBackendAddressPoolsId $null -SubnetId $vnet.Subnets[0].Id

    #
    # Machine, count, and OS profile
    #
    Write-Log "Creating machine profile"
    $vmss = New-AzureRmVmssConfig -Location $Location -SkuCapacity $ClusterSize -SkuName "Standard_DS3" -UpgradePolicyMode "manual"
    Add-AzureRmVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmss -Name "PsClusterDemo" -Primary $true -IPConfiguration $ipConfig
    Set-AzureRmVmssOsProfile -VirtualMachineScaleSet $vmss -ComputerNamePrefix "pscl" -AdminUsername "vmadmin" -AdminPassword "Pa55w0rd!@#$"

    #
    # Setup storage accounts to Users
    #
    Write-Log "Assigning storage accounts to storage profile"
    $storageProfile = "PsClusterStorageProfile"
    $imagePublisher = "MicrosoftWindowsServer"; $imageOffer = "WindowsServer"; $imageSku = "2012-R2-Datacenter"
    $vhdContainers = @("https://11172016vmssa1.blob.core.windows.net/vhds",
        "https://11172016vmssa2.blob.core.windows.net/vhds",
        "https://11172016vmssa3.blob.core.windows.net/vhds")
        
    Set-AzureRmVmssStorageProfile -VirtualMachineScaleSet $vmss `
        -ImageReferencePublisher $imagePublisher `
        -ImageReferenceOffer $imageOffer `
        -ImageReferenceSku $imageSku `
        -ImageReferenceVersion "latest" `
        -Name $storageProfile `
        -VhdContainer $vhdContainers `
        -OsDiskCreateOption "FromImage" `
        -OsDiskCaching "None"

    #
    # Create the cluster
    #
    Write-Log "Creating cluster..."
    New-AzureRmVmss -ResourceGroupName $ResourceGroupName -Name $ClusterName -VirtualMachineScaleSet $vmss
}

# #
# # Update the capcity
# #
# $vmss.Sku.Capacity = 8
# Update-AzureRmVmss -ResourceGroupName $ResourceGroupName -Name $ClusterName -VirtualMachineScaleSet $vmss

# #
# # Change the machine series (this will error)
# #
# $vmss.Sku.Name = "Standard_D1"
# Stop-AzureRmVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $ClusterName
# Remove-AzureRmVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $ClusterName
# New-AzureRmVmss -ResourceGroupName $ResourceGroupName -Name $ClusterName -VirtualMachineScaleSet $vmss

# #
# # Cleanup
# #
# Remove-AzureRmVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $ClusterName