$ErrorActionPreference = 'Stop'
$config = $env:SOC_ANSIBLE_CONFIG | ConvertFrom-Json
if (!$config -or !$env:SOC_ANSIBLE_PRIVATE_KEY -or !$env:SOC_DSRM_PASSWORD) {
    throw 'Missing Terraform configuration or secrets for Ansible.'
}
$linuxHome = & wsl.exe -d Ubuntu --exec printenv HOME
if ($LASTEXITCODE -ne 0 -or !$linuxHome) { throw 'WSL Ubuntu is not available.' }
$python = "$($linuxHome.Trim())/.venvs/soc-ansible/bin/python"
& wsl.exe -d Ubuntu --exec $python -c 'import ansible'
if ($LASTEXITCODE -ne 0) { throw 'Prepare the ~/.venvs/soc-ansible environment in WSL before applying.' }
& wsl.exe -d Ubuntu --exec ssh -V
if ($LASTEXITCODE -ne 0) { throw 'openssh-client is required in WSL Ubuntu.' }

function Get-HostPublicKey {
    param([string]$Name, [string]$CommandId, [string]$Script)
    $response = & az vm run-command invoke --subscription $config.subscription_id `
        --resource-group $config.resource_group --name $Name --command-id $CommandId `
        --scripts $Script --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to retrieve SSH host key from $Name via Azure." }
    $result = $response | ConvertFrom-Json
    $messages = ($result.value | ForEach-Object { $_.message }) -join "`n"
    $match = [regex]::Match($messages, '(?m)^SOC_HOST_KEY=(ssh-ed25519 [A-Za-z0-9+/=]+)')
    if (!$match.Success) { throw "Azure did not return a valid SSH host key from $Name." }
    return $match.Groups[1].Value
}

$linuxKey = Get-HostPublicKey $config.linux_vm 'RunShellScript' `
    'printf SOC_HOST_KEY=; cat /etc/ssh/ssh_host_ed25519_key.pub'
$windowsKey = Get-HostPublicKey $config.windows_vm 'RunPowerShellScript' `
    "Write-Output ('SOC_HOST_KEY=' + (Get-Content C:\ProgramData\ssh\ssh_host_ed25519_key.pub))"
$runner = & wsl.exe -d Ubuntu --exec wslpath -a (Join-Path $PSScriptRoot 'run.py')
if ($LASTEXITCODE -ne 0) { throw 'Failed to resolve runner path in WSL Ubuntu.' }

$request = @{
    config       = $config
    private_key  = $env:SOC_ANSIBLE_PRIVATE_KEY
    dsrm         = $env:SOC_DSRM_PASSWORD
    linux_key    = $linuxKey
    windows_key  = $windowsKey
}
# Windows PowerShell may prepend a UTF-8 BOM when piping to native executables.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$request | ConvertTo-Json -Depth 5 -Compress |
    & wsl.exe -d Ubuntu --exec $python $runner
if ($LASTEXITCODE -ne 0) { throw "Ansible failed with exit code $LASTEXITCODE. Configuration is incomplete." }
