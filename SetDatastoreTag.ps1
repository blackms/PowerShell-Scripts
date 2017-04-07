<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		Given a list of Datastore Names, this script will assign a Tag to them
	
	.PARAMETER csvFile
		String representing the full path of the file
		The file must be structured like this:
		-----------------------------
		DatastoreName,Tag,TagCategory
		DatastoreName,Tag,TagCategory
		...
		-----------------------------
	
	.NOTES
		===========================================================================
		Created on:   	31/03/2017 11:16
		Created by:   	Alessio Rocchi <arocchi@vmware.com>
		Organization: 	VMware
		Filename:
		===========================================================================
	.TODO
		La prima riga del CSV sara` i Tag su cui lo script andra` a lavorare.
		Lo script dovra` rimuovere i tag non specificati rispetto a quelli della prima riga
        Il numero dei Tag puo` essere potenzialmente infinito
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

class vcConnector : System.IDisposable
{
	[String]$Username
	[String]$Password
	[String]$vCenter
	[PSObject]$server
	
	static [vcConnector]$instance
	
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

class Content{
	[System.Collections.Generic.List[System.String]]$availableTags
	[System.Collections.Generic.List[System.String]]$elements
	
	Content()
	{
	}
	
	Content([String]$filePath)
	{
		if ((Test-Path -Path $filePath) -eq $false)
		{
			throw ("Cannot find file: {0}" -f ($filePath))
		}
		try
		{
			# Cast the Get-Content return type to Generic List of Strings in order to avoid fixed-size array
			$this.elements = [System.Collections.Generic.List[System.String]](Get-Content -Path $filePath -ea SilentlyContinue -wa SilentlyContinue)
			$this.availableTags = $this.raw[0].split(',')
			# Delete the first element aka availableTags
			$this.elements.RemoveAt(0)
		}
		catch
		{
			throw ("Error reading the file: {0}" -f ($filePath))
		}
	}
}

try
{
	$vc = [vcConnector]::new().GetInstance()
	$csvContent = [Content]::new($csvFile)
	
	foreach ($element in $csvContent.elements)
	{
		# Get the Datastore Name
		[System.String]$datastoreName = $element.split(',')[0]
		# Create a List of Tags which will be assigned to the Datastore
		[System.Collections.Generic.List[TagAssignment]]$tagsToAssign = $element.split(',')[1..$element.Lenght-1] | ForEach-Object { Get-TagAssignment -Server $_ }
		# Get Datastore object by the given Datastore Name, first field of the the line
		$datastore = Get-Datastore -Name $datastoreName -ea Stop
		# Iterate the assigned Datastore Tags
		foreach ($tag in ($datastore | Get-TagAssignment))
		{
			# Check if the current tag is one of the available ones.
			if ($tag -in $csvContent.availableTags)
			{
				# Remove the current assigned Tag
				Write-Host("Removing Tag: {0}" -f ($tag))
			}
		}
		# Finally add the new set of tags to the Datastore
		foreach ($tag in $tagsToAssign)
		{
			Write-Host("Trying to assign Tag: {0} to Datastore: {1}" -f ($tag, $datastoreName))
			# Assign the Tag
			New-TagAssignment -Entity $datastore -Tag $tag -WhatIf
		}		
	}
}
catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException]
{
	Write-Error("VIException: {0}" -f ($Error[0].Exception.Message))
	exit
}
catch
{
	Write-Error $Error[0].Exception.Message
	exit
}
finally
{
	# Let be assured that the vc connection will be disposed.
	$vc.Dispose()
}