<#
	.SYNOPSIS
		Create CategoryTag and Tags on a vCenter Server
	
	.DESCRIPTION
		Given a CSV with old and new name, this script will rename all of the DS according to it.
	
	.PARAMETER vCenter
		Name of the vCenter Server on which to perform the operations.
	
	.PARAMETER categoryCsvFile
		Csv file formatted which containts the categories to be added.
	
	.PARAMETER vcUsername
		Username for vCenter
	
	.PARAMETER vcPassword
		Password for vCenter
	
	.PARAMETER tagCsvFile
		Csv formatted file which contains the tags to be added.
	
	.NOTES
		===========================================================================
		Created on:   	05/05/2017 11:03
		Created by:   	Alessio Rocchi <arocchi@vmware.com>
		Organization: 	VMware
		Filename:     	CreateTagsAndCategory.ps1
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$vCenter,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$categoryCsvFile,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$vcUsername,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$vcPassword,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$tagCsvFile
)

class vcConnector: System.IDisposable
{
	[String]$Username
	[String]$Password
	[String]$vCenter
	[PSObject]$server
	
	static [vcConnector]$instance
	
	vcConnector() {
		$this.coonect()	
	}
	
	vcConnector($Username, $Password, $vCenter)
	{
		Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
		
		$this.Username = $Username
		$this.Password = $Password
		$this.vCenter = $vCenter
		$this.connect()
	}
	
	vcConnector($vcCredential, $vCenter)
	{
		Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
		
		$this.vcCredential = $vcCredential
		$this.vCenter = $vCenter
		$this.connect()
	}
	
	[void] hidden connect()
	{
		try
		{
			if ([String]::IsNullOrEmpty($this.Username) -or [String]::IsNullOrEmpty($this.Password))
			{
				$vcCredential = Get-Credential
				Connect-VIServer -Server $this.vCenter -Credential $this.vcCredential -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
			}
			else
			{
				Connect-VIServer -Server $this.vCenter -User $this.Username -Password $this.Password -WarningAction SilentlyContinue -ErrorAction Stop
			}
			Write-Debug("Connected to vCenter: {0}" -f $this.vCenter)
		}
		catch
		{
			Write-Error($Error[0].Exception.Message)
			exit
		}
	}
	
	[void] Dispose()
	{
		Write-Debug("Called Dispose Method of Instance: {0}" -f ($this))
		Disconnect-VIServer -WarningAction SilentlyContinue -Server $this.vCenter -Force -Confirm:$false | Out-Null
	}
	
	static [vcConnector] GetInstance()
	{
		if ([vcConnector]::instance -eq $null)
		{
			[vcConnector]::instance = [vcConnector]::new()
		}
		
		return [vcConnector]::instance
	}
}

[vcConnector]$vcConnection = [vcConnector]::new($vcUsername, $vcPassword, $vCenter)

try
{
	$categoryList = Get-Content -Path $categoryCsvFile -ea Stop -wa SilentlyContinue
	$tagList = Get-Content -Path $tagCsvFile -ea Stop -wa SilentlyContinue
}
catch
{
	Write-Error("Cannot Open file: {0}. With Error: {1}" -f ($_.Exception.Source, $_.Exception.Message))
	exit 1
}

# Process Categories
foreach ($cat in $categoryList)
{
	[System.String]$categoryName = $cat.ToString().split(",")[0]
	[System.String]$categoryDescription = $cat.ToString().split(",")[1]
	
	try
	{
		New-TagCategory -Name $categoryName -Description $categoryDescription -Cardinality "Multiple"
	}
	catch
	{
		Write-Error("Cannot Create Category: {0}. Error: {1}" -f ($oldName, $_.Exception.Message))
		exit 1
	}
}

# Process Tags
foreach ($tag in $tagList)
{
	[System.String]$tagName = $tag.ToString().split(",")[0]
	try
	{
		[VMware.VimAutomation.ViCore.Impl.V1.VIObjectImpl]$tagCategory = Get-TagCategory -Name $tag.ToString().split(",")[1] -ea Stop -wa SilentlyContinue
	}
	catch
	{
		Write-Error("Cannot find TagCategory: {0}" -f $tag.ToString().split(",")[1])
		exit 1
	}
	[System.String]$tagDescription = $tag.ToString().split(',')[2]
	
	try
	{
		New-Tag -Name $tagName -Category $tagCategory -Description $tagDescription -Confirm:$false -ea Stop -wa SilentlyContinue
	}
	catch
	{
		Write-Error("Cannot Create Tag: {0}. With Error: {1}" -f ($tagName, $_.Exception.Message))
		exit 1
	}
}

write-Host("Finished.")


# Better to be sure...
$vcConnection.Dispose()
