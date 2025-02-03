param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$VaultName,

    [Parameter(Mandatory = $true)]
    [string]$VMName
)

# Authenticate if not already logged in
if (-not (Get-AzContext)) {
    Write-Host "Logging into Azure..."
    Connect-AzAccount
}

# Retrieve the Recovery Services Vault
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroup -Name $VaultName
if (-not $vault) {
    Write-Host "Error: Vault '$VaultName' not found in resource group '$ResourceGroup'."
    exit 1
}
Write-Host "Vault Found: $($vault.Name)"

# Set the Vault Context explicitly
Set-AzRecoveryServicesAsrVaultContext -Vault $vault
Write-Host "Vault context set successfully."

# Retrieve Recovery Fabrics
$fabrics = Get-AzRecoveryServicesAsrFabric
if (-not $fabrics) {
    Write-Host "Error: No recovery fabrics found."
    exit 1
}
$fabric = $fabrics | Select-Object -First 1
Write-Host "Fabric Found: $($fabric.Name)"

# Retrieve the Protection Container (Fixed Command)
$container = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric
if (-not $container) {
    Write-Host "Error: No protection container found in fabric '$($fabric.Name)'."
    exit 1
}
Write-Host "Protection Container Found: $($container.Name)"

# Retrieve all Replicated VMs
$allReplicatedVMs = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container
Write-Host "Available Replicated VMs in Protection Container:"
$allReplicatedVMs | Format-Table FriendlyName, ID

# Find the VM inside the replicated items
$replicatedVM = $allReplicatedVMs | Where-Object { $_.FriendlyName -eq $VMName }
if (-not $replicatedVM) {
    Write-Host "Error: Replicated VM '$VMName' not found in protection container."
    Write-Host "Available Replicated VMs: $($allReplicatedVMs.FriendlyName -join ', ')"
    exit 1
}
Write-Host "Replicated VM Found: $($replicatedVM.FriendlyName)"

# Start the Test Failover
$job = Start-AzRecoveryServicesAsrTestFailoverJob -ReplicationProtectedItem $replicatedVM -FailoverDirection "PrimaryToRecovery"

Write-Host "Test Failover Job Started: $($job.Name)"

# Poll for completion
while ($true) {
    $currentJob = Get-AzRecoveryServicesAsrJob -Name $job.Name
    if ($currentJob.State -eq "InProgress" -or $currentJob.State -eq "NotStarted") {
        Write-Host "Job status: $($currentJob.State). Waiting 30 seconds..."
        Start-Sleep -Seconds 30
    } else {
        Write-Host "Job Finished with Status: $($currentJob.State)"
        break
    }
}

# Check if Failover Succeeded
if ($currentJob.State -ne "Succeeded") {
    Write-Host "Test Failover job failed or partially succeeded. Check logs."
    exit 1
}

Write-Host "Test Failover successful!"
exit 0
