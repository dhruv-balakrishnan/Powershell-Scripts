<#
    .SYNOPSIS
        Starts background jobs on ADO VM's

    .DESCRIPTION
        This script enables you to run any other script or command on a set of specified machines. The script uses PoshRSJob to enable simple Runspace implementation for parallel calls.
        
        The agents to service are specified in a mapping.json file which the script will read. Using pool id data from the file, it will get the list of agents in each specified pool
        and remember which agents to service based on the names we specified in the .json file.

        While the .json mapping file is convenient for batches of servers in logical groups, one disadvantage is if you want to specify a select few agents instead of all agents matching a string. 
        In this case, just specify a text file with the agents you'd like to service.

        NOTE: If required, will install the PoshRSJob module which is required for this script to work. This will require user approval for first time use if not already present.

     .PARAMETER PAT
        THe PAT to use when connecting to ADO services

     .PARAMETER serverListPath
        The path to the text file containing the list of servers to work on.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$PAT = "",
    [Parameter(Mandatory=$false)]
    [string]$serverListPath = $null
)

Write-Host -ForegroundColor Cyan "Checking Prerequisites.."

if (Get-Module -ListAvailable -Name PoshRSJob) {
    Import-Module PoshRSJob
    Write-Host "Requirements Satisfied." -ForegroundColor Green
} 
else {
    Write-Host "Requirements not met. Installing.." -ForegroundColor Yellow
    Install-Module PoshRSJob
    Import-Module PoshRSJob
    Write-Host "Done." -ForegroundColor Green
}

$debug = $true

[System.Collections.ArrayList]$ServicingList = @()
[System.Collections.ArrayList]$MappedAgents = @()
[System.Collections.ArrayList]$MappedObects = @()
[System.Collections.ArrayList]$RemainingAgents = @()
$collectionMaps = New-Object 'system.collections.generic.dictionary[string,int]'

$mappingFile = Get-Content "$($PSScriptRoot)\mapping.json" | ConvertFrom-Json -ErrorAction Stop

#Setup
$apiVersion = "api-version=5.1-preview.1"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f '',$PAT)))

<#
    Reads in the mapping file and stores the maps(filters) that will be used to choose which agents to service.
#>
function ReadMappingFile()
{
    $mappingList = @()
    foreach($collection in $mappingFile.Collections) {

        if($collection.active -match "true") 
        {
            if($debug) { Write-Host "  Reading $($collection.name)" }

            foreach($pool in $collection.pools) 
            {
                if($pool.active -match "true")
                {
                    if($debug) { Write-Host "    Reading $($pool.name)" }

                    foreach($map in $pool.maps)
                    {
                        if($map.active -match "true")
                        {
                            if($debug) { Write-Host "      Adding $($map.agent)" -ForegroundColor Green }

                            #Currently this adds an object for EVERY mapping, not every pool. Could be optimized
                            $MappedObects.Add(
                                [PSCustomObject]@{
                                    collection = $collection.name
                                    poolID = $pool.id
                                    agent = $map.agent
                                }
                            )
                        } else {
                            if($debug) { Write-Host "      Skipping $($map.agent)" -ForegroundColor Yellow }
                        }
                    }
                } else {
                    if($debug) { Write-Host "    Skipping $($pool.name)" -ForegroundColor Yellow}
                }
            }
        } else {
            if($debug) { Write-Host "  Skipping $($collection.name)" -ForegroundColor Yellow}
        }
    }
}

#Base function to handle API calls to ADO.
function GetADOData() {
    param(
        [string]$URL
    )

    if($debug) {
        Write-Host "  API Call: $URL" -ForegroundColor Yellow
    }

    $res = $null

    try 
    {
        $res = Invoke-RestMethod -Uri $URL -Method GET -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -ErrorAction Continue
    } catch 
    {
        
        if ($RestError)
        {
            $HttpStatusCode = $RestError.ErrorRecord.Exception.Response.StatusCode.value__
            $HttpStatusDescription = $RestError.ErrorRecord.Exception.Response.StatusDescription
    
            Throw "Http Status Code: $($HttpStatusCode) `nHttp Status Description: $($HttpStatusDescription)"
        } else {
        }
    }

    return $res
}

<#
    Gets the list of agents that match our filters (from the mapping file) and stores all of them in a list for later use.
#>
function GetAgentsToService(){
    
    foreach($map in $MappedObects)
    {
        $URI = "https://" + $map.collection + ".visualstudio.com/_apis/distributedtask/pools/" + $map.poolID + "/agents?includeCapabilities=true&" + $apiVersion

        $APIAgentList = GetADOData($URI)

        if($null -eq $APIAgentList)
        {
            Write-Error "  Error fetching agent list. Exiting."
            return
        }

        Write-Host "  Got Agents in $($map.poolID)"
        #Write-Host $APIAgentList.value

        foreach($VM in $APIAgentList.value) 
        {
            if($debug) { Write-Host "    Checking $($VM.name))" -ForegroundColor Yellow }
            #Check if this agent is contained in this objects mappings
              if($VM.name -match $map.agent) 
              {
                  if($debug) 
                  {                
                     Write-Host "    $($VM.name) matches $($map.agent)" -ForegroundColor Yellow
                  }

                  if($VM.Name -match "agent-") {
                        $VM.Name -replace "agent-"
                  }
                  $ServicingList.Add($VM.Name)
              }
        }
    }

}

# Runs code if the invoke/work failed.
function FailurePostRun() {
    Param(
        [string]$server,
        [string]$message
    )
    Write-Host "  $message"
    $RemainingAgents.Add($server)
}

#Check if we are using a text file with the server list or getting batches through ADO

if($serverListPath) 
{
    if($debug) { Write-Host "`nReading Server List.." -ForegroundColor Cyan}
    $ServicingList = gc $serverListPath

} else {

    if($debug) { Write-Host "`nReading Mapping File.." -ForegroundColor Cyan}
    ReadMappingFile

    if($debug) { Write-Host "`nGetting agents to service.." -ForegroundColor Cyan}
    GetAgentsToService
}

$count = $ServicingList.Count - 1


$message  = "Ready."
$question = "Continue Execution on $($count + 1) servers?"

$choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

$decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)

if ($decision -ne 0) 
{
  Write-Host 'Operation Cancelled, exiting' -ForegroundColor Cyan
  Exit 0
}


if($debug) { Write-Host "`nWorking with $($count + 1) servers." -ForegroundColor Cyan}

if($debug) { Write-Host "`nExecuting commands.." -ForegroundColor Cyan}

#Manage parallelism with the throttle parameter. Will depend on what your scripts do. 

0..$count | Start-RSJob -Name {$_} -ArgumentList $ServicingList, $RemainingAgents -Throttle 5 {
    $list = $Using:ServicingList
    $list2 = $Using:RemainingAgents
    $server = $list[$_]
    
    
    <#
        ADD OR REMOVE COMMANDS/SCRIPTS HERE AS DESIRED. Bunch of examples below.
    #>

    "$($server):"

    #$ret = C:\Tools\Scripts\PowershellScripts\SetVirtualMemory.ps1 -ComputerName $server -MaximumPageSize 20480 -PagefilePath "C:\pagefile.sys" -numberOfProcessors 2
    #$ret = C:\Tools\Scripts\PowershellScripts\UpdateVS.ps1 -computername $server -update 
    #$ret = C:\Tools\Scripts\PowershellScripts\InstallGenericExe.ps1 -server $server -psExecPath C:\Tools\Scripts\PowershellScripts\PSTools -installFileLocation C:\Tools\Scripts\PowershellScripts -installFileName wdksetup.exe
    #C:\Tools\Scripts\PowershellScripts\SearchForProgram.ps1 -program "Windows Driver Kit"
    #Invoke-Command -ComputerName $server -ScriptBlock {Start-Service "vstsagent.*"}

    if($ret -eq 100) {
        "  Execution Successful"
        "  $status"
    } elseif($ret -eq 101) {
        "  Execution Skipped Due to Build"
    } elseif($ret -eq 102) {
        "  Execution Failed"
        $list2.Add($server)
    } elseif($ret -eq 103) {
        "  Execution Successful, but requires reboot"
    } elseif($ret -eq 104) {
        "  Execution Cancelled"
    } else {
        "  $ret"
    }

} | Wait-RSJob -ShowProgress | Receive-RSJob

$RemainingAgents | Out-File "$($PSScriptRoot)\Remaining.txt"