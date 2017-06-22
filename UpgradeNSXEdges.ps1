<#
	.SYNOPSIS
		With this script is possible to upgrade all the NSX Edges managed by the given NSX Manager
	
	.DESCRIPTION
		Upgrade NSX Edges given an NSX Manager
	
	.PARAMETER Username
		NSX Manager Username (admin)
	
	.PARAMETER Password
		NSX Manager Password
	
	.PARAMETER NSXManager
		NSX Manager IP or Hostname
	
	.PARAMETER TargetVersion
		Target Version to upgrade Edges to (ie. 6.3.2)
	
	.NOTES
		===========================================================================
		Created on:   	22/06/2017 14:05
		Created by:   	Alessio Rocchi <arocchi@vmware.com>
		Organization: 	VMware
		Filename:     	UpgradeNSXEdges.ps1
		===========================================================================
#>
[CmdletBinding()]
param
(
	[ValidateNotNullOrEmpty()]
	[System.String]$Username,
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$Password,
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$NSXManager,
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[System.String]$TargetVersion
)

class HttpHandler: System.Management.Automation.PSCustomObject
{
	[System.String]$Uri = [System.String]::new()
	[System.String]$Headers
	
	hidden [System.String]$Username = [System.String]::new()
	hidden [System.String]$Password = [System.String]::new()
	
	HttpHandler([System.String]$Uri)
	{
		$this.Uri = $Uri
	}
	
	HttpHandler([System.String]$Uri, [System.String]$Headers)
	{
		$this.Uri = $Uri
		$this.Headers = $Headers
	}
	
	[System.String]CreateAuthHeaders([System.String]$Username, [System.String]$Password)
	{
		$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Username + ":" + $Password))
		return @{ "Authorization" = "Basic $auth" }
	}
	
	[System.Management.Automation.PSCustomObject]Get([System.String]$uri, [System.String]$method="", [System.String]$args="", [System.String]$contentType="application/xml")
	{
		[System.String]$requestUri = $Uri + $method + $args
		# For now we will use PowerShell API
		# [System.Net.WebRequest]$Request = [System.Net.WebRequest]::Create($requestUri)
		try
		{
			$r = Invoke-WebRequest -Uri $requestUri -Headers = $this.Headers -ContentType $contentType -ErrorAction:Stop
			if ($r.StatusCode -ne "200")
			{
				throw
			}
		}
		catch
		{
			return $null
		}
		return $r
	}
}

class Edge : HttpHandler
{
	[System.Xml.XmlDocument]$Content
	[System.String]$Id
	[System.String]$Name
	[System.String]$Version
	
	Edge([System.String]$Username, [System.String]$Password, [System.String]$Uri) : base($Uri)
	{
		$this.Username = $Username
		$this.Password = $Password
		$this.Headers = [HttpHandler].CreateAuthHeaders($Username, $Password)
	}
	
	[Boolean] Upgrade()
	{
		$requestUri = $this.Uri + "/" + $this.Id + "?action=upgrade"
		try
		{
			$c = [HttpHandler].Get($this.Uri)
		}
		catch
		{
			return $false
		}
		return $true
	}
}

class Edges: HttpHandler
{
	[System.Xml.XmlDocument]$Content
	
	Edges([System.String]$Username, [System.String]$Password, [System.String]$Uri) : base($Uri)
	{
		$this.Username = $Username
		$this.Password = $Password
		$this.Headers = [HttpHandler].CreateAuthHeaders($Username, $Password)
		$this.Content = [HttpHandler].Get($this.Uri, "?startIndex=0&pageSize=1")
	}
	
	[System.String] GetTotalNumberOfEdges()
	{
		return $this.Content.pagedEdgeList.edgePage.pagingInfo.totalCount
	}
	
	[System.Collections.ArrayList[Edge]] GetAllEdges()
	{
		try
		{
			$c = [HttpHandler].Get($this.Uri, "?startIndex=0&pageSize=", $this.GetTotalNumberOfEdges())
		}
		catch
		{
			return $null
		}
		$_edges = @()
		foreach ($e in $c.pagedEdgeList.edgePage.edgeSummary)
		{
			[Edge]$edge = [Edge]::new($this.Username, $this.Password, $this.Uri)
			$edge.Name = $e.Name
			$edge.Id = $e.objectId
			$edge.Version = $e.appliancesSummary.vmVersion
			$_edges += $edge
		}
		return $_edges
	}
}


##Get total number of edges
$Request = "https://$NSXManager/api/4.0/edges"
[Edges]$Edges = [Edges]::new($Username, $Password, $Request)

##Upgrade all edges
$edgesObject = $Edges.GetAllEdges()
foreach ($edge in $edgesObject)
{
	$edge.Upgrade()
}

