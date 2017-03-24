<#
	.SYNOPSIS
		A brief description of the GetDriverInformation.ps1 file.
	
	.DESCRIPTION
		Get ESXi Driver Informations.
	
	.PARAMETER vCenter
		vCenter Server
	
	.NOTES
		===========================================================================
		Created on:   	24/03/2017 09:05
		Created by:   	Alessio Rocchi <arocchi@vmwrae.com>
		Organization:   VMware
		Filename:     	GetDriverInformation.ps1
		===========================================================================
#>
[CmdletBinding(ConfirmImpact = 'None',
			   SupportsShouldProcess = $false)]
param
(
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true,
			   Position = 1)]
	[ValidateNotNullOrEmpty()]
	[String]$vCenter
)

Import-Module -Name VMware.VimAutomation.Core -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null

<#
	.SYNOPSIS
		A brief description of the GetHBAInformation function.
	
	.DESCRIPTION
		Return HBA Information
	
	.PARAMETER esx
		VMHost object
	
	.PARAMETER esxcliv2
		Esxcli V2 Object
	
	.EXAMPLE
		PS C:\> GetHBAInformation -esx $value1
	
	.NOTES
		Additional information about the function.
#>
function GetHBAInformation
{
	[CmdletBinding(SupportsShouldProcess = $false)]
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   Position = 1)]
		[ValidateNotNullOrEmpty()]
		[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$esx,
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   Position = 2,
				   HelpMessage = 'Esxcli V2 Object')]
		[ValidateNotNullOrEmpty()]
		[System.Object]$esxcliv2
	)
	
	Begin
	{
		
	}
	Process
	{
		$hostHba = Get-VMHostHBA -VMHost $esx -Type FibreChannel | Where-Object { $_.Status -eq "online" } |
		Select-Object @{ N = "Datacenter"; E = { $datacenter.Name } },
					  @{ N = "VMHost"; E = { $esx.Name } },
					  @{ N = "HostName"; E = { $($_.VMHost | Get-VMHostNetwork).HostName } },
					  @{ N = "version"; E = { $esx.version } },
					  @{ N = "Manufacturer"; E = { $esx.Manufacturer } },
					  @{ N = "Hostmodel"; E = { $esx.Model } },
					  @{ Name = "SerialNumber"; Expression = { $esx.ExtensionData.Hardware.SystemInfo.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Key -eq "Servicetag" } | Select-Object -ExpandProperty IdentifierValue } },
					  @{
			N = "Cluster"; E = {
				if ($esx.ExtensionData.Parent.Type -ne "ClusterComputeResource") { "Stand alone host" }
				else
				{
					Get-view -Id $esx.ExtensionData.Parent | Select-Object -ExpandProperty Name
				}
			}
		},
					  Device, Model, Status,
					  @{ N = "WWPN"; E = { ((("{0:X}" -f $_.NodeWorldWideName).ToLower()) -replace "(\w{2})", '$1:').TrimEnd(':') } },
					  @{ N = "WWN"; E = { ((("{0:X}" -f $_.PortWorldWideName).ToLower()) -replace "(\w{2})", '$1:').TrimEnd(':') } },
					  @{ N = "Fnicvendor"; E = { $esxcliv2.hardware.pci.list.Invoke() | Where-Object { $hba -contains $_.VMKernelName } | Select-Object -ExpandProperty VendorName } },
					  @{ N = "enicdriver"; E = { $esxcliv2.system.module.get.Invoke(@{ module = "elxnet" }).version } },
					  @{
			N = "lpfcdriver"; E = {
				$esxcliv2.system.module.get.Invoke(@{ module = "lpfc" }.version)
			}
		}
		@{ N = "Enicvendor"; E = { $esxcliv2.hardware.pci.list.Invoke() | Where-Object { $nic -contains $_.VMKernelName } | Select-Object -ExpandProperty VendorName } }
		return $hostHba
	}
	End
	{
		
	}
}

try
{
	$credential = Get-Credential -Message "Insert vCenter Username"
	Connect-VIServer $vCenter -Credential $credential -WarningAction SilentlyContinue
}
catch [Exception] {
	$exception = $_.Exception
	Write-Error("Cannot connect to vCenter: {0} with error: {1}" -f ($vCenter, $exception.Message))
}

$report = New-Object System.Collections.ArrayList
foreach ($datacenter in Get-Datacenter)
{
	foreach ($esx in Get-VMHost -Location $datacenter)
	{
		Write-Host("Processing: {0}" -f $esx.Name)
		$esxcliv2 = Get-EsxCli -V2 -VMHost $esx
		$nic = Get-VMHostNetworkAdapter -VMHost $esx | Select-Object -First 1 | Select-Object -ExpandProperty Name
		$hba = Get-VMHostHBA -VMHost $esx -Type FibreChannel | Where-Object { $_.Status -eq "online" } | Select-Object -First 1 | Select-Object -ExpandProperty Name
		$elem = Get-VMHostHBA -VMHost $esx -Type FibreChannel | Where-Object { $_.Status -eq "online" }
		$resultObject = New-Object -TypeName 'System.Management.Automation.PSObject'
		Add-Member -InputObject $resultObject -Name "Datacenter" -MemberType NoteProperty -Value $datacenter.Name
		Add-Member -InputObject $resultObject -Name "VMHost" -MemberType NoteProperty -Value $esx.Name
		Add-Member -InputObject $resultObject -Name "HostName" -MemberType NoteProperty -Value $($esx | Get-VMHostNetwork).HostName
		Add-Member -InputObject $resultObject -Name "version" -MemberType NoteProperty -Value $esx.version
		Add-Member -InputObject $resultObject -Name "Manufacturer" -MemberType NoteProperty -Value $esx.Manufacturer
		Add-Member -InputObject $resultObject -Name "HostModel" -MemberType NoteProperty -Value $esx.Model
		$serialNumber = $esx.ExtensionData.Hardware.SystemInfo.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Key -eq "Servicetag" } | Select-Object -ExpandProperty IdentifierValue
		Add-Member -InputObject $resultObject -Name "SerialNumber" -MemberType NoteProperty -Value $serialNumber
		if ($esx.ExtensionData.Parent.Type -ne "ClusterComputeResource")
		{
			$cluster = "Stand alone host"
		}
		else
		{
			$cluster = Get-view -Id $esx.ExtensionData.Parent | Select-Object -ExpandProperty Name
		}
		Add-Member -InputObject $resultObject -Name "Device" -MemberType NoteProperty -Value $_.Device
		Add-Member -InputObject $resultObject -Name "Model" -MemberType NoteProperty -Value $_.Model
		Add-Member -InputObject $resultObject -Name "Status" -MemberType NoteProperty -Value $_.Status
		$wwpn = ((("{0:X}" -f $_.NodeWorldWideName).ToLower()) -replace "(\w{2})", '$1:').TrimEnd(':')
		Add-Member -InputObject $resultObject -Name "WWPN" -MemberType NoteProperty -Value $wwpn
		$wwn = ((("{0:X}" -f $_.PortWorldWideName).ToLower()) -replace "(\w{2})", '$1:').TrimEnd(':')
		Add-Member -InputObject $resultObject -Name "WWN" -MemberType NoteProperty -Value $wwn
		$fNicVendor = $esxcliv2.hardware.pci.list.Invoke() | Where-Object { $hba -contains $_.VMKernelName } | Select-Object -ExpandProperty VendorName
		Add-Member -InputObject $resultObject -Name "Vendor" -MemberType NoteProperty -Value $fNicVendor
		$elxNetDriver = $esxcliv2.system.module.get.Invoke(@{ module = "elxnet" }).version
		Add-Member -InputObject $resultObject -Name "ElxnetDriver" -MemberType NoteProperty -Value $elxNetDriver
		$LpfcDriver = $esxcliv2.system.module.get.Invoke(@{ module = "lpfc" }).version
		Add-Member -InputObject $resultObject -Name "LpfcDriver" -MemberType NoteProperty -Value $LpfcDriver
		$report.Add($resultObject)
	}
}

$report | Export-Csv

