<#
.SYNOPSIS
  Connects to Azure and stops of all VMs in parallel for the scheduled resource group
.DESCRIPTION
  This runbook connects to Azure and stops all ARM Azure VMs within a resource group 
  You should attach a schedule to this runbook to run it at a specific time. 
  REQUIRED AUTOMATION ASSETS
  1. An Automation variable asset called "SubscriptionId" that contains the GUID for this Azure subscription. 
     To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.
  2. An Automation credential asset called "AzureCred" that contains the Azure AD user credential with authorization for this subscription.
.PARAMETER Operation
   Operation will either be Startup or Shutdown
.PARAMETER ResourceGroup
   Name of the ResourceGroup that hosts the VMs
.PARAMETER IgnoreScheduleShutdown
   Mandatory Yes or No
   This is generally set to Yes, however when you want to exclude a particular resource group changing the variable will
.NOTES
   AUTHOR: Sean McDonnell
   LASTEDIT: 27/05/2019
#>

workflow Server_Shutdown_Startup
{
    param (
            [Parameter(Mandatory=$TRUE)][String]  $Operation,
            [Parameter(Mandatory=$TRUE)][String]  $ResourceGroup,
            [Parameter(Mandatory=$TRUE)][boolean] $IgnoreScheduleShutdown,
            [Parameter(Mandatory=$TRUE)][boolean] $RunOnWeekend
    )

    $CredentialAssetName = "AzureCred"; # Name of your Azure Credential
    $SubscriptionID = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXX"; # SubscriptionID
    $Cred = Get-AutomationPSCredential -Name $CredentialAssetName;

    if(!$Cred) {

        Throw "Could not find an Automation Credential Asset named '${CredentialAssetName}'. Make sure you have created one in this Automation Account."
    }

    Login-AzAccount -Credential $Cred -Subscription $SubscriptionID

    if($Operation -match "Shutdown")
    {
        Write-output "Operation: Shutdown"
        $VMList = Get-AzVM -ResourceGroupName $ResourceGroup | Where-Object { $_.Tags.ContainsKey("StartupPriority") -and $_.Tags.ContainsKey("ScheduledShutdown")}
        for ($i = 100; $i -ge 0; $i--)
        {
            if ($IgnoreScheduleShutdown)
            {
                $VMsToTurnOff = $VMList | Where-Object { $_.Tags.Item("StartupPriority") -eq $i }
            }
            else
            {
                $VMsToTurnOff = $VMList | Where-Object { $_.Tags.Item("StartupPriority") -eq $i -and $_.Tags.Item("ScheduledShutdown") -eq "Yes" }
            }

            foreach -parallel ($VM in $VMSToTurnOff)
            {
                Write-output "Shutting down -> $($VM.Name)"
                Stop-AzVM -Name $VM.Name -ResourceGroupName $ResourceGroup -Force
            }
        }
    }

    if($Operation -match "Startup")
    {
        Write-output "Operation: Startup"
        $a = (Get-Date).ToUniversalTime().AddHours(1)
        $day = $a.DayOfWeek
        if (($day -like "*Saturday*") -or ($day -like "*Sunday*"))
        {
            write-output "Weekend detected......"

            if (!$RunOnWeekend)
            {
              Write-output "RunOnWeekend = False. Exit Server_Shutdown-Startup Script!"
              Exit
            }
        }
        
        $VMList = Get-AzVM -ResourceGroupName $ResourceGroup | Where-Object { $_.Tags.ContainsKey("StartupPriority") }
        for ($i = 0; $i -lt 100; $i++)
        {
            $VMSToTurnOn = $VMList | Where-Object {$_.Tags.Item("StartupPriority") -eq $i}
            foreach -parallel ($VM in $VMSToTurnOn)
            {
                Write-output "Starting up -> $($VM.Name)"
                Start-AzVM -Name $VM.Name -ResourceGroupName $ResourceGroup
            }
        }
    }
}