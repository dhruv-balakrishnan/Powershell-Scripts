<#
    .SYNOPSIS
        Installs an .exe file on a remote machine. 

    .DESCRIPTION
        Uses psexec to install any .exe file on remote machines. This script was originally used to maintain VM's in Microsofts 
        implementation of Pools and Queues in Azure DevOps, hence the checks for a service and process 

    .PARAMETER
        server: The name of the remote machine.
        Ex. RemoteMachine01

    .PARAMETER
        outfile: The output file if you want to store agents where the install was not successful

    .PARAMETER
        installFileLocation: Path to the folder where the .exe resides
        Ex: C:\Users\User\Downloads\Windows Kits\10\WDK

    .PARAMETER
        installFileName: Name of the .exe
        Ex: wdksetup.exe

    .PARAMETER
        psExecPath: Path to the folder where psexec.exe resides
        Ex: C:\Tools\Scripts\PSTools

    .Example Run
        .\InstallGenericExe.ps1 pkges-labe22 C:\Tools\Scripts\TextFiles\WDKToDo.txt "C:\Users\user\Downloads\Windows Kits\10\WDK" wdksetup.exe C:\Tools\Scripts\PSTools

    .Notes
        This only installs on one machine. Use in conjunction with RunGenericCommand.ps1 to parallelize the operation.
        This DOES NOT WORK for .msu's. Use the Install KB script instead.
#>

param (
    [Parameter(Mandatory=$True)][string]$server,
    [Parameter(Mandatory=$False)][string]$outfile,
    [Parameter(Mandatory=$True)][string]$installFileLocation,
    [Parameter(Mandatory=$True)][string]$installFileName,
    [Parameter(Mandatory=$True)][string]$psExecPath
)

[System.Collections.ArrayList]$NotDone = @()

function RunInstaller($installFileName) {
    & "C:\$installFileName" /quiet /norestart
}

Start-Sleep -Seconds 5
Write-Host $server

#Copy Installer to Server
if(!(Test-Path (Join-Path "\\$server\c$\" $installFileName))) {
    robocopy $installFileLocation "\\$server\c$\" $installFileName /r:1
} else {
    Write-Host "File Already Exists, continuing.."
}    

if(Test-Path (Join-Path "\\$server\c$\" $installFileName)) {

   & (Join-Path $psExecPath "PsExec.exe") -s \\$server c:\$installFileName /quiet /norestart

   #Confirm Install with custom exit codes. This will depend on the exe you're running. Examples here.

   if($LASTEXITCODE -eq 0) {
      Write-Host -ForegroundColor Green "Install Complete".
   }

   if($LASTEXITCODE -eq 2008) {
      Write-Host -ForegroundColor Green "Install Already Exists".
   }

} else {
  Write-Host "Path isn't found, not installing."
  $NotDone.Add($server)
}
    
    

if($outfile) {
   $NotDone | Out-File -filepath $outFile -Append
}


