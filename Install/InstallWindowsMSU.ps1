<#
    .SYNOPSIS
        Installs a KB (.msu) on a remote machine.

    .DESCRIPTION
        This script will install a specific KB onto a list of machines. The basic flow is as follows: 

            1. Check if this is a WS2016 or WS2012 machine. Do nothing (currently) if it is a WS2012 machine
            2. Check if the specified hotfix is installed. Do nothing if it is.
            3. Check if the Hotfix has been copied to the target machine in the specified folder. If not, copy it.
            4. Install the KB.

        How to use the script

        The "&" command used here to run PSExec.exe doesn't work in Powershell ISE. Follow these steps: 

        1. Save the location of this script somewhere.
        2. Open Powershell as admin. 
        3. cd <path to the folder where the script is located>
        4. .\InstallKb.ps1 <path to infile> <path to outfile> <path to KB> <folder name to copy KB to>
     
    .PARAMETER
        $inpath : The path to the list of servers to perform the install on.
        Ex: C:\Users\User\Desktop\Scripts\servers.txt

    .PARAMETER
        $outPath : The script will save servers that the install didn't run on into this fiel.
        Ex: C:\Users\User\Desktop\Scripts\notDone.txt

    .PARAMETER
        $psExecPath : The script uses PSExec.exe to perform the KB installation. This is the path to the folder that contains that exe.
        Ex: C:\Users\User\Desktop\Scripts\PSTools

    .PARAMETER
        $localKBPath : The path to the KB in your local machine.
        Ex: C:\users\User\Desktop\KB.msu

    .EXAMPLE
        cd C:\Users\User\Desktop\Scripts
        .\InstallKb.ps1 C:\Users\User\Desktop\Scripts\servers.txt C:\Users\User\Desktop\Scripts\notDone.txt C:\Users\User\Desktop\Scripts\PSTools C:\users\User\Desktop\KB.msu

    .NOTE
        As currently implemented, the name of the .msu needs to be "KB.msu". Can be changed to be more accomodating of course.
#>


Param (
    #Path to the input file
    [Parameter(Mandatory = $true)]
    [string][ValidateNotNullOrEmpty()]$inPath,

    #Path to put the output file to
    [Parameter(Mandatory = $false)]
    [string][ValidateNotNullOrEmpty()]$outPath,

    #Path to PSExec in your local machine
    [Parameter(Mandatory = $true)]
    [string][ValidateNotNullOrEmpty()]$psExecPath,

    #Path to the KB in your local machine
    [Parameter(Mandatory = $true)]
    [string][ValidateNotNullOrEmpty()]$localKBPath
)

$Servers = gc $inPath 
$done = @()
$notDone = @()

foreach ($Server in $Servers){

  Write-Host -ForegroundColor Cyan "Server: "$Server

  # Copy update package to local folder on server
  $OSVersion = Invoke-Command -ComputerName $server -ScriptBlock { Get-WmiObject -Class Win32_OperatingSystem | ForEach-Object -MemberName BuildNumber }

  if(![string]::IsNullOrEmpty($OSVersion) -and ($OSVersion -like '*16299*' -or $OSVersion -like '*17134*' -or $OSVersion -like '*14393*')) {
        #Check for Hotfix
        if(!(Get-Hotfix -id KB4345418 -computername $Server -ErrorAction SilentlyContinue)) {
            
            #Check for .msu
            if(!(Test-Path "\\$Server\c$\KB.msu")) {
                Write-Host "Copying KB to => \\$Server\c$\"
                robocopy $localKBPath "\\$Server\c$\" KB.msu
            }

            Write-Host "Installing KB from \\$Server\c$\"
            & (Join-Path $psExecPath "PsExec.exe") -s \\$Server wusa.exe c:\KB.msu /quiet /norestart

            #These exit codes are official Windows KB exit codes.
            switch ($LASTEXITCODE) {
                3010 {
                    Write-Host -ForegroundColor Green "Install Success, needs a reboot."
                    $done += $Server
                }

                3 {
                    Write-Host -ForegroundColor Red "Path to KB not found."
                    $notDone += $Server  
                }

                1618 {
                    Write-Host -ForegroundColor Yellow "Another installation is already in progress."
                }

                2359302 {
                    Write-Host -ForegroundColor Green "Install Probably Success, needs a reboot."
                    $done += $Server
                }
            }

        } else {
            Write-Host -ForegroundColor Green "KB4345418 is already installed"
        }
  } else {
    Write-Host -ForegroundColor Yellow "WS 2012 Server."
    $notDone += $server
  }
  Write-Host "------------------------------------"
}

if($outPath) {
    $notDone | Out-File $outPath -Append
}

