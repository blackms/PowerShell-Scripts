<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		Given a CSV with old and new name, this script will rename all of the DS according to it.
	
	.PARAMETER vCenter
		A description of the vCenter parameter.
	
	.PARAMETER csvFile
		A description of the csvFile parameter.
	
	.PARAMETER vcUsername
		A description of the vcUsername parameter.
	
	.PARAMETER vcPassword
		A description of the vcPassword parameter.
	
	.NOTES
		===========================================================================
		Created on:   	04/05/2017 14:55
		Created by:   	Alessio Rocchi <arocchi@vmware.com>
		Organization: 	VMware
		Filename:     	RenameMultipleDS.ps1
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
	[System.String]$csvFile,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$vcUsername,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$vcPassword
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
	$dsList = Get-Content -Path $csvFile -ea Stop -wa SilentlyContinue
}
catch
{
	Write-Host("Cannot Open CSV File.")
	exit 1
}

foreach ($ds in $dsList)
{
	[System.String]$oldName = $ds.ToString().split(",")[0]
	[System.String]$newName = $ds.ToString().split(",")[1]
	
	try
	{
		$dsObj = Get-Datastore -Name $oldName -ea Stop
	}
	catch
	{
		write-Error("Cannot find DS with name: {0}" -f ($oldName))
		exit 1
	}
	
	Write-Host("Renaming DS: {0} to {1}" -f ($dsObj.Name, $newName))
	try
	{
		Set-Datastore -Datastore $dsObj -Name $newName -Confirm:$false
	}
	catch
	{
		Write-Error("Cannot rename DS: {0}. Error: {1}" -f ($dsObj.Name, $_.Exception.Message))
	}
}

write-Host("Finished.")


# Better to be sure...
$vcConnection.Dispose()
