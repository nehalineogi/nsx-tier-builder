function Remove-NSXTier {

<#  
.SYNOPSIS  Removes a virtual network tier in VMware NSX
.DESCRIPTION Removes a virtual network tier in VMware NSX
.NOTES  Author:  Chris Wahl, @ChrisWahl, WahlNetwork.com
.PARAMETER NSX
	NSX Manager IP or FQDN
.PARAMETER NSXPassword
	NSX Manager credentials with administrative authority
.PARAMETER NSXUsername
	NSX Manager username with administrative authority
.PARAMETER JSONPath
	Path to your JSON configuration file
.EXAMPLE
	PS> Remove-NSXTier -NSX nsxmgr.tld -JSONPath "c:\path\prod.json"
#>

[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true,Position=0,HelpMessage="NSX Manager IP or FQDN")]
	[ValidateNotNullorEmpty()]
	[String]$NSX,
	[Parameter(Mandatory=$true,Position=1,HelpMessage="NSX Manager credentials with administrative authority")]
	[ValidateNotNullorEmpty()]
	[System.Security.SecureString]$NSXPassword,
	[Parameter(Mandatory=$true,Position=2,HelpMessage="Path to your JSON configuration file")]
	[ValidateNotNullorEmpty()]
	[String]$JSONPath,
	[String]$NSXUsername = "admin" #defaults to admin if nothing is passed to the parameter
	)
	
Process {

# Create NSX authorization string and store in $head
$nsxcreds = New-Object System.Management.Automation.PSCredential "admin",$NSXPassword
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NSXUsername+":"+$($nsxcreds.GetNetworkCredential().password)))
$head = @{"Authorization"="Basic $auth"}
$uri = "https://$nsx"

# Plugins and version check
if ($Host.Version.Major -lt 3) {throw "PowerShell 3 or higher is required"}

# Parse configuration from json file
$config = Get-Content -Raw -Path $jsonpath | ConvertFrom-Json
	if ($config) {Write-Host -BackgroundColor:Black -ForegroundColor:Yellow "Status: Parsed configuration from json file."}
	else {throw "I don't have a config, something went wrong."}

# Combine switches and transit into a build list (easier than messing with a custom PS object!)
$switchlist = @()
foreach ($_ in $config.switches) {$switchlist += $_.name}
$switchlist += $config.transit.name

# Allow untrusted SSL certs
	add-type @"
	    using System.Net;
	    using System.Security.Cryptography.X509Certificates;
	    public class TrustAllCertsPolicy : ICertificatePolicy {
	        public bool CheckValidationResult(
	            ServicePoint srvPoint, X509Certificate certificate,
	            WebRequest request, int certificateProblem) {
	            return true;
	        }
	    }
"@
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Remove edge

$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges" -Headers $head -ContentType "application/xml" -ErrorAction:Stop
[xml]$rxml = $r.Content
foreach ($_ in $rxml.pagedEdgeList.edgePage.edgeSummary) {
	if ($_.name -eq $config.edge.name) {
		$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/$($_.objectId)" -Headers $head -Method:Delete -ContentType "application/xml" -ErrorAction:Stop
		if ($r.StatusCode -eq "204") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully deleted $($_.name) edge."}
		}
	}

# Remove router

$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges" -Headers $head -ContentType "application/xml" -ErrorAction:Stop
[xml]$rxml = $r.Content
foreach ($_ in $rxml.pagedEdgeList.edgePage.edgeSummary) {
	if ($_.name -eq $config.router.name) {
		$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/$($_.objectId)" -Headers $head -Method:Delete -ContentType "application/xml" -ErrorAction:Stop
		if ($r.StatusCode -eq "204") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully deleted $($_.name) router."}
		}
	}

# Wait for the deletes
Sleep 10

# Remove switches
$r = Invoke-WebRequest -Uri "$uri/api/2.0/vdn/virtualwires" -Headers $head -ContentType "application/xml" -ErrorAction:Stop
[xml]$rxml = $r.Content
foreach ($_ in $rxml.virtualWires.dataPage.virtualWire) {
	if ($switchlist -contains $_.name) {
		$r = Invoke-WebRequest -Uri "$uri/api/2.0/vdn/virtualwires/$($_.objectId)" -Headers $head -Method:Delete -ContentType "application/xml" -ErrorAction:Stop
		if ($r.StatusCode -eq "200") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully deleted $($_.name) switch."}
		}
	}

	} # End of process
} # End of function
