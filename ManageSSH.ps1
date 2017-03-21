<#
.SYNOPSIS Start and Stop SSH Service
.DESCRIPTION Start and Stop SSH Service on a single cluster, host or an entire vCenter
.NOTES Author: Alessio Rocchi
.NOTES AuthorEmail: arocchi@vmware.com
.PARAMETER vCenter
    [String] vCenter Server to use [Mandatory]
.PARAMETER user
    [String] Username for vCenter [Not Mandatory]
.PARAMETER Cluster
    [STRING] Cluster to iterate [Not Mandatory]
.PARAMETER Action
    [STRING] Start/Stop [Mandatory]
.EXAMPLE
    ManageSSH.ps1 -vCenter "vc.org.local" -Cluster "Antani" -Action Start
#>

param (
	[Parameter(
			   Position = 0,
			   Mandatory = $true,
			   ValueFromPipeline = $true
	)]
	[String]$vCenter,
	[Parameter(
			   Position = 1,
			   Mandatory = $false,
			   ValueFromPipeline = $true
	)]
	[String]$cluster = $null,
	[Parameter(
			   Position = 2,
			   Mandatory = $true,
			   ValueFromPipeline = $true
	)]
	[ValidateSet("Start", "Stop")]
	[String]$Action
)

Get-module -ListAvailable PowerCLI* | Import-module -ErrorAction SilentlyContinue | Out-Null

function StartSshService()
{
	param (
		[Parameter(
				   Position = 0,
				   Mandatory = $true,
				   ValueFromPipeline = $true
		)]
		[VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$VMHost
	)
	
	try
	{
		foreach ($cHost in $VMHost)
		{
			Write-Host -ForegroundColor GREEN "Starting SSH Service on: " -NoNewline
			Write-Host -ForegroundColor YELLOW "$cHost"
			Get-VMHostService -VMHost $cHost | Start-VMHostService -HostService ($_ | Get-VMHostService | Where-Object { $_.Key -eq "TSM-SSH" })
		}
	}
	catch
	{
		write-Error("Cannot Start SSH on Host: {}" -f $cHost)
	}
}

function StopSshService()
{
	param (
		[Parameter(
				   Position = 0,
				   Mandatory = $true,
				   ValueFromPipeline = $true
		)]
		[VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$VMHost
	)
	
	try
	{
		foreach ($cHost in $VMHost)
		{
			Write-Host -ForegroundColor GREEN "Setting Startup Policy on: " -NoNewline
			Write-Host -ForegroundColor YELLOW "$cHost"
			Get-VMHostService -VMHost $cHost | Stop-VMHostService -HostService ($_ | Get-VMHostService | Where-Object { $_.Key -eq "TSM-SSH" }) -Confirm:true
		}
	}
	catch
	{
		Write-Error("Cannot Stop SSH Service on Host: " -f $cHost)
	}
}

try
{
	Connect-VIServer -Server $vCenter -user $user
}
catch
{
	write-error("Cannot connect to vCenter: {}" -f ($vcenter))
}

if ($cluster -eq [String]::Empty)
{
	$HostsToProcess = Get-VMHost
}
else
{
	$HostsToProcess = Get-Cluster -Name $cluster | Get-VMHost
}

switch ($Action.ToLower())
{
	"start" {
		StartSshService -VMHost $HostsToProcess
	}
	"stop" {
		StopSshService -VMHOST $HostsToProcess
	}
}