<#
.SYNOPSIS
    Deploy a Win11 VM on Proxmox via Terraform. Auto-increments VM ID.
.USAGE
    .\deploy.ps1                  # Create next VM
    .\deploy.ps1 -Name "MyVM"    # Create with custom name
    .\deploy.ps1 -Destroy 201    # Destroy specific VM
    .\deploy.ps1 -List           # List VMs we've created
#>
param(
    [string]$Name,
    [int]$Count = 1,
    [int]$Destroy,
    [switch]$DestroyAll,
    [switch]$List
)

$ErrorActionPreference = "Stop"

$ProxmoxUrl = $env:PVE_URL ?? "https://192.168.1.210:8006"
$ProxmoxUser = $env:PVE_USER ?? "root@pam"
$ProxmoxPassword = $env:PVE_PASSWORD
$Node = $env:PVE_NODE ?? "pve"

if (-not $ProxmoxPassword) {
    $ProxmoxPassword = Read-Host "Proxmox password" -AsSecureString | 
        ForEach-Object { [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($_)) }
}
$VmIdStart = 200  # Our range starts here
$VmIdEnd = 299    # Our range ends here

function Get-PVEAuth {
    $authJson = curl.exe -k -s -d "username=$ProxmoxUser" -d "password=$ProxmoxPassword" "$ProxmoxUrl/api2/json/access/ticket"
    $auth = $authJson | ConvertFrom-Json
    return @{
        Ticket = $auth.data.ticket
        CSRF   = $auth.data.CSRFPreventionToken
    }
}

function Invoke-PVE {
    param($Method, $Path, $Body, $Auth)
    $args = @("-k", "-s", "-X", $Method, "-b", "PVEAuthCookie=$($Auth.Ticket)", "-H", "CSRFPreventionToken: $($Auth.CSRF)")
    if ($Body) { 
        foreach ($kv in $Body.GetEnumerator()) {
            $args += @("-d", "$($kv.Key)=$($kv.Value)")
        }
    }
    $args += "$ProxmoxUrl$Path"
    $result = & curl.exe @args
    if ($result) { return $result | ConvertFrom-Json }
}

function Get-ExistingVMs {
    param($Auth)
    $vms = Invoke-PVE -Method GET -Path "/api2/json/nodes/$Node/qemu" -Auth $Auth
    return $vms.data | Where-Object { $_.vmid -ge $VmIdStart -and $_.vmid -le $VmIdEnd }
}

function Get-NextVmId {
    param($Auth)
    $existing = Get-ExistingVMs -Auth $Auth
    $usedIds = @($existing | ForEach-Object { $_.vmid })
    for ($id = $VmIdStart; $id -le $VmIdEnd; $id++) {
        if ($id -notin $usedIds) { return $id }
    }
    throw "No free VM IDs in range $VmIdStart-$VmIdEnd!"
}

# --- Auth ---
$auth = Get-PVEAuth

# --- List ---
if ($List) {
    $vms = Get-ExistingVMs -Auth $auth
    if ($vms) {
        Write-Host "`nTerraform Win11 VMs ($VmIdStart-$VmIdEnd):" -ForegroundColor Cyan
        foreach ($vm in $vms) {
            $status = if ($vm.status -eq "running") { "🟢" } else { "⚫" }
            Write-Host "  $status $($vm.vmid) - $($vm.name) [$($vm.status)]"
        }
    } else {
        Write-Host "No VMs in range $VmIdStart-$VmIdEnd" -ForegroundColor Yellow
    }
    exit
}

# --- Destroy All ---
if ($DestroyAll) {
    $vms = Get-ExistingVMs -Auth $auth
    if (-not $vms) {
        Write-Host "No VMs to destroy." -ForegroundColor Yellow
        exit
    }
    Write-Host "Destroying $($vms.Count) VM(s)..." -ForegroundColor Yellow
    foreach ($vm in $vms) {
        Write-Host "  Stopping $($vm.vmid) ($($vm.name))..." -ForegroundColor Yellow
        Invoke-PVE -Method POST -Path "/api2/json/nodes/$Node/qemu/$($vm.vmid)/status/stop" -Auth $auth 2>$null
    }
    Start-Sleep 5
    foreach ($vm in $vms) {
        Write-Host "  Destroying $($vm.vmid)..." -ForegroundColor Yellow
        Invoke-PVE -Method DELETE -Path "/api2/json/nodes/$Node/qemu/$($vm.vmid)" -Auth $auth | Out-Null
        Remove-Item "terraform-$($vm.vmid).tfstate*" -Force -ErrorAction SilentlyContinue
    }
    Write-Host "All VMs destroyed." -ForegroundColor Green
    exit
}

# --- Destroy ---
if ($Destroy) {
    Write-Host "Stopping VM $Destroy..." -ForegroundColor Yellow
    Invoke-PVE -Method POST -Path "/api2/json/nodes/$Node/qemu/$Destroy/status/stop" -Auth $auth 2>$null
    Start-Sleep 5
    Write-Host "Destroying VM $Destroy..." -ForegroundColor Yellow
    Invoke-PVE -Method DELETE -Path "/api2/json/nodes/$Node/qemu/$Destroy" -Auth $auth | Out-Null
    Remove-Item "terraform-$Destroy.tfstate*" -Force -ErrorAction SilentlyContinue
    Write-Host "VM $Destroy destroyed." -ForegroundColor Green
    exit
}

# --- Create ---
Write-Host "Deploying $Count VM(s)..." -ForegroundColor Cyan
$createdVms = @()

for ($c = 0; $c -lt $Count; $c++) {
    $vmId = Get-NextVmId -Auth $auth
    $vmName = if ($Name -and $Count -eq 1) { $Name } elseif ($Name) { "$Name-$vmId" } else { "Win11-Test-$vmId" }

    Write-Host "`nCreating VM $vmId ($vmName)... [$($c+1)/$Count]" -ForegroundColor Cyan

    $stateFile = "terraform-$vmId.tfstate"
    terraform apply -auto-approve -state="$stateFile" -var="vm_id=$vmId" -var="vm_name=$vmName"
    if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed for VM $vmId" }

    $createdVms += $vmId
}

# Refresh auth
$auth = Get-PVEAuth

# Start all VMs and send keypresses
foreach ($vmId in $createdVms) {
    Write-Host "Starting VM $vmId..." -ForegroundColor Cyan
    Invoke-PVE -Method POST -Path "/api2/json/nodes/$Node/qemu/$vmId/status/start" -Auth $auth | Out-Null
}

# Spam spacebar on all VMs
Write-Host "Sending keypresses..." -ForegroundColor Yellow
for ($i = 0; $i -lt 20; $i++) {
    foreach ($vmId in $createdVms) {
        curl.exe -k -s -X PUT -d "key=spc" -b "PVEAuthCookie=$($auth.Ticket)" -H "CSRFPreventionToken: $($auth.CSRF)" "$ProxmoxUrl/api2/json/nodes/$Node/qemu/$vmId/sendkey" | Out-Null
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "`n$Count VM(s) deployed and booting into Windows Setup!" -ForegroundColor Green
