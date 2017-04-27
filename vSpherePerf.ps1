<#
	.SYNOPSIS
		A brief description of the vSpherePerf.ps1 file.
	
	.DESCRIPTION
		vSphere Performance Collector
	
	.PARAMETER vCenterFilePath
		Define the file containing the vCenters list
	
	.PARAMETER LogFile
		Path for the Log file
	
	.NOTES
		===========================================================================
		Created on:   	27/04/2017 12:08
		Author:   		Alessandro De Vecchi <adevecchi@vmware.com>
		Author2:     	Alessio Rocchi <arocchi@vmware.com>
		Organization: 	VMware
		Filename:     	vSpherePerf.ps1
		===========================================================================
#>
[CmdletBinding(ConfirmImpact = 'None',
			   SupportsShouldProcess = $false)]
param
(
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true,
			   ValueFromPipelineByPropertyName = $true,
			   ValueFromRemainingArguments = $false,
			   Position = 0,
			   HelpMessage = 'Define the file containing the vCenters list')]
	[ValidateNotNullOrEmpty()]
	[System.String]$vCenterFilePath,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true,
			   ValueFromPipelineByPropertyName = $true,
			   ValueFromRemainingArguments = $false,
			   Position = 1,
			   HelpMessage = 'Path for the Log file')]
	[AllowNull()]
	[AllowEmptyString()]
	[System.String]$LogFile
)

class Logging {
	Logging()
	{
		if ($this.GetType() -eq [Logging])
		{
			throw ("Class must be Implemented")
		}
	}
	
	[System.Void] Info([System.String]$message)
	{
		throw ("Method Must be implemented.")
	}
	
	[System.Void] Warning([System.String]$message)
	{
		throw ("Method Must be implemented.")
	}
	
	[System.Void] Error([System.String]$message)
	{
		throw ("Method Must be implemented.")
	}
	
	[System.Void] Critical([System.String]$message)
	{
		throw ("Method Must be implemented.")
	}
}

class FileLogger: Logging
{
	# Properties
	[System.String]$LogFile
	[int32]$maxFileSize = 512kb
	[int32]$Rotation = 1
	
	#Constructor
	FileLogger([System.String]$LogFile): base ()
	{
		$this.LogFile = $LogFile
	}
	
	hidden [boolean] isRoteable([System.Object]$fileItem)
	{
		if ($fileItem.Lenght -gt $this.maxFileSize)
		{
			return True
		}
		return False
	}
	
	hidden [System.Void] writeToFile([System.String]$message)
	{
		$timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		try
		{
			$ErrorActionPreference = "Stop"
			$TestLogSize = Get-Item $this.LogFile
		}
		catch
		{
			Write-Error("[{0}] Fail to write the log file: {1}" -f ($timeStamp, $this.LogFile))
		}
		finally
		{
			$ErrorActionPreference = 'Continue'
		}
		
		if ($this.isRoteable((Get-Item $this.LogFile)))
		{
			[System.String]$rotatedFile = ("{0}.{1}" -f ($this.LogFile, $this.Rotation))
			Write-Debug("[{0}] Performing log rotation on file: {1}" -f ($timeStamp, $rotatedFile))
			Add-Content $this.LogFile -value ("[{0}] Performing log rotation on file: {1}" -f ($timeStamp, $rotatedFile))
			Rename-Item -Path $this.LogFile -NewName $rotatedFile
			$this.Rotation++
		}
		Add-Content -Path $this.LogFile -Value ("[{0}] {1}" -f ($timeStamp, $message))
	}
	
	# Method Implementation
	[System.Void] Info([System.String]$message)
	{
		
	}
}
