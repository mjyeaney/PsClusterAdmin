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
        [Int]$ClusterSize,

        [parameter(Mandatory=$true)]
        [Int]$StoragePoolSize
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
    if ((Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) -eq $null){
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
    } else {
        Write-Log "Resource group already exists - continuing"
    }

    #
    # We need a pool of storage accounts
    #
    Write-Log "Creating storage account pool"

    # Create storage pool
    $vhdContainers = @()
    $date = [DateTime]::Now
    1..$StoragePoolSize | % {
        $name = [String]::Format("{0}{1}{2}vmst{3}", $date.Month, $date.Day, $date.Year, $_)
        if ((Test-AzureName -Storage $name) -eq $false){
            New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                -Name $name `
                -SkuName Standard_LRS `
                -Location $Location
            $vhdContainers += [String]::Format("https://{0}.blob.core.windows.net/vhds", $name)
        } else {
            Write-Error "Unable to create required storage account - exiting"
            Break
        }
    }

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
    $imagePublisher = "MicrosoftWindowsServer" 
    $imageOffer = "WindowsServer"
    $imageSku = "2012-R2-Datacenter"
        
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