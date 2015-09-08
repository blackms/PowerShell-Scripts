$global:ObjProperty = @("VMHost","vCenter")
$ArubaVMWTools = New-Object -TypeName 'System.Management.Automation.PSObject'
	$global:ObjProperty | ForEach-Object {
		Add-Member -InputObject $ArubaVMWTools -Name $_ -MemberType NoteProperty -Value ""
	}
	$Connect = {
		Param (	[Parameter(Mandatory = $true,ValueFromPipeline = $true)]
				[String]$vCenter
			)
		Try { Connect-VIServer $vCenter -WarningAction SilentlyContinue -ErrorAction Stop } 
		Catch {
			$ExcObj = $_
			Log-Exception -ExcObj $ExcObj
		}
		$ArubaVMWTools.vCenter = $vCenter
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType ScriptMethod -Name 'Connect' -Value $Connect
	$Disconnect = {
		Disconnect-VIServer -Force:$true -Confirm:$false -Server $ArubaVMWTools.vCenter -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType Scriptmethod -Name 'Disconnect' -Value $Disconnect		
	$SetPolicy = {
		Param ( 
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[String]$vSwitch,
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[Object[]]$VMHostArray,
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[Object[]]$VLAN,
			[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 4)]
			[String]$Type
		)
		switch ($Type.ToLower()) {
			"public" {
				$FT = $false
				$AP = $false
				$MC = $false
			}
			"private" {
				$FT = $true
				$AP = $true
				$MC = $true
			}
			default {
				$FT = $false
				$AP = $false
				$MC = $false
			}
		}
		$VMHostArray |
		ForEach-Object {
			$VMHost = $_
			$Esx = Get-VMHost $VMHost | Get-View
			$NetworkSystem = Get-View $Esx.ConfigManager.NetworkSystem
			$PortGroupSpec = New-Object VMWare.Vim.HostPortGroupSpec
			$VLAN |
			ForEach-Object {
				$Cur_VLAN = $_
				Write-Host -NoNewline -ForegroundColor Yellow ("`r [ ] - Configured vLAN: {0}" -f $Cur_VLAN)
				Try {
					$PGName = $Cur_VLAN
					$PortGroupSpec.vSwitchName = $vSwitch
					$PortGroupSpec.Name = $Cur_VLAN
					$PortGroupSpec.VlanID = (Get-VirtualPortGroup -Name $Cur_VLAN).VLanId
					$PortGroupSpec.Policy = New-object VMware.Vim.HostNetworkPolicy
					$PortGroupSpec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
					$PortGroupSpec.Policy.Security.ForgedTransmits = $FT
					$PortGroupSpec.Policy.Security.AllowPromiscuous = $AP
					$PortGroupSpec.Policy.Security.MacChanges = $MC
					$NetworkSystem.UpdatePortGroup($PGName, $PortGroupSpec)
				} Catch {
					Write-Error $_ |fl *
					Disconnect-VIServer -Confirm:$false
					exit
				}
			}
			Write-Host ""
		}
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType ScriptMethod -Name 'SetPolicy' -Value $SetPolicy
	$AddPG = {
		Param (
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[Object[]]$PGs,
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[Object[]]$Hosts,
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[String]$vSwitch,
			[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
			[String]$Type
		)
		$Hosts | 
		ForEach {
			$CurHost = Get-VMHost $_
			$vSwitchObj = $CurHost | Get-VirtualSwitch -Name $vSwitch
			$PGs |
			ForEach {
				$Cur_vLAN = $_
				Try {
					New-VirtualPortGroup -Name $Cur_VLAN -VirtualSwitch $vSwitchObj -VLanId $Cur_VLAN | Out-Null
				} Catch {
					Log-Exception -ExcObj $_
				}
				$ArubaVMWTools.SetPolicy($vSwitch,$CurHost,$Cur_vLAN,$Type)
			}
		}
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType ScriptMethod -Name 'AddPG' -Value $AddPG
	$LoadHosts = {
		Return Get-VMHost
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType ScriptMethod -Name 'LoadHosts' -Value $LoadHosts
	$AddvSwitch = {
		Param (
			[Parameter(Mandatory=$true)]
			[String]$vSwitch,
			[Parameter(Mandatory=$true)]
			[String]$VMnics
		)
		Try {
			Get-VirtualSwitch -Name $vSwitch -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
			Write-Host -ForegroundColor Red (" [ ] - {0} Already Present." -f $vSwitch)
		} Catch {
			$vmniclist = $VMnics
			try {
				$ArubaTool.VMHost | New-VirtualSwitch -Name $vSwitch -Nic $vmniclist -Confirm:$false >$null
			} Catch {
				Write-Host $_ |fl *
				exit
			}
		}
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType ScriptMethod -Name 'AddvSwitch' -Value $AddvSwitch
	$CallAddUserToGroup = {
		Param (
			[Parameter(Mandatory=$true)]
			[Object[]]$ObjListComputers,
			[Parameter(Mandatory=$true)]
			[String]$Group,
			[Parameter(Mandatory=$true)]
			[String]$User
		)
	
		$ObjListComputers | %{
			$Computer = $_
			try {
				$RemoteHostGroup = [ADSI]"WinNT://$computer/$Group,group"
				$RemoteHostGroup.psbase.Invoke("Add",([ADSI]"WinNT://$Domain/$User").path)
				Write-Host ("User: {0}, Added to Group: {1}, In Host: {2}" -f ($User,$Group,$Computer))
			} catch {
				Write-Host $_
			}
		}
	}
	Add-Member -InputObject $ArubaVMWTools -MemberType ScriptMethod -Name 'AddUsertToGroup' -Value $CallAddUserToGroup
