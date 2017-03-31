<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		Given a list of Datastore Names, this script will assign a Tag to them
	
	.PARAMETER csvFile
		String representing the full path of the file
	
	.NOTES
		===========================================================================
		Created on:   	31/03/2017 11:16
		Created by:   	Alessio Rocchi <arocchi@vmware.com>
		Organization: 	VMware
		Filename:
		===========================================================================
#>
[CmdletBinding()]
param
(
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$csvFile,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
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

<#
	.SYNOPSIS
		Import Csv from file into PSObject
	
	.DESCRIPTION
		A detailed description of the ImportCsv function.
	
	.PARAMETER csvFilePath
		String representing the path of the file
	
	.EXAMPLE
		PS C:\> ImportCsv -csvFilePath 'Value1'
	
	.NOTES
		Additional information about the function.
#>
function ImportCsv
{
	[CmdletBinding(ConfirmImpact = 'None',
				   SupportsShouldProcess = $false)]
	[OutputType([System.Management.Automation.PSCustomObject])]
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$csvFilePath
	)
	
	Begin
	{
		
	}
	Process
	{
		try
		{
			if ((Test-Path -Path $csvFilePath) -eq $false)
			{
				throw "Csv File Not Found."
			}
			return Import-Csv -Path $csvFilePath -WarningAction SilentlyContinue -ErrorAction Stop -Header Datastore, Tag, TagCategory
		}
		catch
		{
			throw $Error[0].Exception.Message
		}
	}
	End
	{
		
	}
}

try
{
	if ([String]::IsNullOrEmpty($Username) -or [String]::IsNullOrEmpty($Password))
	{
		$vcCredential = Get-Credential
		Connect-VIServer -Server $vCenter -Credential $vcCredential -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
	}
	else
	{
		Connect-VIServer -Server $vCenter -User $Username -Password $Password -WarningAction SilentlyContinue -ErrorAction Stop
	}
}
catch
{
	Write-Error($Error[0].Exception.Message)
	exit
}

try
{
	$csvContent = ImportCsv -csvFilePath $csvFile
	
	foreach ($element in $csvContent)
	{
		$datastore = Get-Datastore -Name $element.Datastore -ea Stop
		$tag = Get-Tag -Name $element.Tag -ea Stop
		Write-Host("Assigning Tag: {0} to Datastore: {1}" -f ($element.Tag, $element.Datastore))
		New-TagAssignment -Entity $datastore -Tag $tag
	}
}
catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException] {
	Write-Error("VIException: {0}" -f ($Error[0].Exception.Message))
	exit
}
catch
{
	Write-Error $Error[0].Exception.Message
	exit
}

Disconnect-VIServer -WarningAction SilentlyContinue -Server $vCenter -Force -Confirm:$false
