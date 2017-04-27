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
		Author:         Alessandro De Vecchi <adevecchi@vmware.com>
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
	
	hidden [System.Void] writeToFile([System.String]$message, [System.String]$timeStamp)
	{
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
		$timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		write-Debug("[{0}] {1}" -f ($timeStamp, $message))
		$this.writeToFile($message, $timeStamp)
	}
}

class vcConnector: System.IDisposable
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

class BackgroundJob
{
	# Properties
	hidden $PowerShell = [powershell]::Create()
	hidden $Handle = $null
	hidden $Runspace = $null
	$Result = $null
	$RunspaceID = $This.PowerShell.Runspace.ID
	$PSInstance = $This.PowerShell
	
	# Constructor (just code block)
	BackgroundJob ([scriptblock]$Code)
	{
		$This.PowerShell.AddScript($Code)
	}
	
	# Constructor (code block + arguments)
	BackgroundJob ([scriptblock]$Code, $Arguments)
	{
		$This.PowerShell.AddScript($Code)
		foreach ($Argument in $Arguments)
		{
			$This.PowerShell.AddArgument($Argument)
		}
	}
	
	# Constructor (code block + arguments + functions)
	BackgroundJob ([scriptblock]$Code, $Arguments, $Functions)
	{
		$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
		$Scope = [System.Management.Automation.ScopedItemOptions]::AllScope
		foreach ($Function in $Functions)
		{
			$FunctionName = $Function.Split('\')[1]
			$FunctionDefinition = Get-Content $Function -ErrorAction Stop
			$SessionStateFunction = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $FunctionName, $FunctionDefinition, $Scope, $null
			$InitialSessionState.Commands.Add($SessionStateFunction)
		}
		$This.Runspace = [runspacefactory]::CreateRunspace($InitialSessionState)
		$This.PowerShell.Runspace = $This.Runspace
		$This.Runspace.Open()
		$This.PowerShell.AddScript($Code)
		foreach ($Argument in $Arguments)
		{
			$This.PowerShell.AddArgument($Argument)
		}
	}
	
	# Start Method
	Start()
	{
		$THis.Handle = $This.PowerShell.BeginInvoke()
	}
	
	# Stop Method
	Stop()
	{
		$This.PowerShell.Stop()
	}
	
	# Receive Method
	[object]Receive()
	{
		$This.Result = $This.PowerShell.EndInvoke($This.Handle)
		return $This.Result
	}
	
	# Remove Method
	Remove()
	{
		$This.PowerShell.Dispose()
		If ($This.Runspace)
		{
			$This.Runspace.Dispose()
		}
	}
	
	# Get Status Method
	[object]GetStatus()
	{
		return $This.PowerShell.InvocationStateInfo
	}
}
