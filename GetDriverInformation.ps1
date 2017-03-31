<#
	.SYNOPSIS
		A brief description of the GetDriverInformation.ps1 file.
	
	.DESCRIPTION
		Get ESXi Driver Informations.
	
	.PARAMETER vCenter
		vCenter Server
	
	.PARAMETER Username
		Username for vCenter
	
	.PARAMETER Password
		Password for vCenter
	
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
	[String]$vCenter,
	[Parameter(ValueFromPipeline = $true,
			   Position = 2)]
	[AllowNull()]
	[String]$Username,
	[Parameter(Position = 3)]
	[AllowNull()]
	[String]$Password
)

Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null

try
{
	if ([String]::IsNullOrEmpty($Username) -or [String]::IsNullOrEmpty($Password))
	{
		$vcCredential = Get-Credential
		Connect-VIServer -Server $vCenter -Credential $vcCredential -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
	}
	else
	{
		Connect-VIServer -Server $vCenter -User $Username -Password $Password -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
	}
}
catch
{
	Write-Error("Error connecting to vCenter: {0}" -f $vCenter)
	exit
}

class HostDeviceInformationList : System.Collections.ArrayList
{
	HostDeviceInformationList() : base()
	{
	}
	
	# This code will convert the hashtable object into an IDictionary implemented one, in order to be able
	# to convert it into a csv.
	ExportToCsv([String]$fileName)
	{
		$this | ForEach-Object {
			new-object psobject -property $_
		} | Export-Csv -Path $fileName -NoTypeInformation -UseCulture
	}
}

class HostDeviceInformation
{
	[System.Object]$esxCliV2
	[PSObject]$VMHostViObj
	[PSObject]$Hba
	[PSObject]$Nic
	[System.Collections.Hashtable]$Data
	
	# Constructor
	HostDeviceInformation([PSObject]$VMHost)
	{
		$this.VMHostViObj = $VMHost
		$this.esxCliV2 = Get-EsxCli -VMHost $this.VMHostViObj -V2
		$this.Hba = Get-VMHostHba -VMHost $this.VMHostViObj -Type FibreChanne | Where-Object { $_.Status -eq "online" }
		$this.Nic = Get-VMHostNetworkAdapter -VMHost $this.VMHostViObj
		$this.Data = [System.Collections.Hashtable]::new()
	}
	
	GetAllData()
	{
		foreach ($hba in $this.Hba)
		{
			if ($this.VMHostViObj.ExtensionData.Parent.Type -ne "ClusterComputeResource")
			{
				$this.Data['Cluster'] = "Standalone Host"
			}
			else
			{
				$this.Data['Cluster'] = Get-view -Id $this.VMHostViObj.ExtensionData.Parent | Select-Object -ExpandProperty Name
			}
			$this.Data['VMHost'] = $this.VMHostViObj.Name
			$this.Data['HostName'] = ($this.VMHostViObj | Get-VMHostNetwork).Hostname
			$this.Data['Version'] = $this.VMHostViObj.version
			$this.Data['Manufacturer'] = $this.VMHostVIObj.Manufacturer
			$this.Data['HostModel'] = $this.VMHostViObj.Model
			$this.Data['SerialNumber'] = $this.VMHostViObj.ExtensionData.Hardware.SystemInfo.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Key -eq "Servicetag" } | Select-Object -ExpandProperty IdentifierValue
			$this.Data['Device'] = $hba.Device
			$this.Data['Model'] = $hba.Model
			$this.Data['Status'] = $hba.Status
			$this.Data['WWPN'] = ((("{0:X}" -f $hba.NodeWorldWideName).ToLower()) -replace "(\w{2})", '$1:').TrimEnd(':')
			$this.Data['WWN'] = ((("{0:X}" -f $hba.PortWorldWideName).ToLower()) -replace "(\w{2})", '$1:').TrimEnd(':')
			$this.Data['Fnicvendor'] = $this.esxCliV2.hardware.pci.list.Invoke() | Where-Object { $hba.Device -contains $_.VMKernelName } | Select-Object -ExpandProperty VendorName
			$this.Data['fnicdriver'] = $this.esxCliV2.system.module.get.Invoke(@{ module = "lpfc" }).version
			$this.Data['enicdriver'] = $this.esxCliV2.system.module.get.Invoke(@{ module = "elxnet" }).version
			$this.Data['Enicvendor'] = $this.esxCliV2.hardware.pci.list.Invoke() | Where-Object { $nic.Device -contains $_.VMKernelName } | Select-Object -ExpandProperty VendorName
		}
		Write-Debug("Collecting Data for host: {0} completed." -f $this.VMHostViObj.Name)
	}
	
	[System.Collections.Hashtable] GetHashtableObject()
	{
		return $this.Data
	}
}

$report = [HostDeviceInformationList]::new()

foreach ($esx in Get-Cluster -Name "WMOBE" | Get-VMHost)
{
	# Create a new instance of the object containing Hashtabled data
	$hostDeviceInformation = [HostDeviceInformation]::new($esx)
	$hostDeviceInformation.GetAllData()
	$report.Add($hostDeviceInformation.GetHashTableObject())
}

$report.ExportToCsv("report.csv")

Disconnect-VIServer -WarningAction SilentlyContinue -Server $vCenter -Force -Confirm:$false




