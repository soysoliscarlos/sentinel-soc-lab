$ErrorActionPreference = 'Stop'
$global:SocLauncherTestState = @{ RunnerExitCode = 0; RunnerCalls = 0; AzureCalls = 0 }

# Local test doubles prevent any real call to Azure CLI or WSL.
function az {
    if ($args -notcontains 'test-subscription' -or $args -notcontains 'test-rg') {
        throw 'Expected subscription and resource group were not explicitly passed.'
    }
    if ($args[([array]::IndexOf($args, '--scripts') + 1)] -match '"') {
        throw 'Script contains double quotes incompatible with Azure CLI invocation on Windows PowerShell.'
    }
    $global:SocLauncherTestState.AzureCalls++
    $global:LASTEXITCODE = 0
    return '{"value":[{"message":"[stdout]\nSOC_HOST_KEY=ssh-ed25519 AAAATEST host\n[stderr]\n"}]}'
}

function wsl.exe {
    $global:LASTEXITCODE = 0
    if ($args -contains 'printenv') { return '/home/test' }
    if ($args -contains 'wslpath') { return '/mnt/c/workspace with spaces/run.py' }
    if ($args -contains '-c' -or $args -contains 'ssh') { return }
    if ($args[-1] -ne '/mnt/c/workspace with spaces/run.py') {
        throw 'Launcher path containing spaces was not preserved.'
    }
    $request = ($input | Out-String) | ConvertFrom-Json
    if ($request.private_key -ne 'TEST-PRIVATE-KEY' -or
        $request.dsrm -ne 'TEST-DSRM' -or
        $request.linux_key -ne 'ssh-ed25519 AAAATEST' -or
        $request.windows_key -ne 'ssh-ed25519 AAAATEST') {
        throw 'JSON payload or host keys do not match expected values.'
    }
    $global:SocLauncherTestState.RunnerCalls++
    $global:LASTEXITCODE = $global:SocLauncherTestState.RunnerExitCode
}

$saved = @{}
foreach ($name in @('SOC_ANSIBLE_CONFIG', 'SOC_ANSIBLE_PRIVATE_KEY', 'SOC_DSRM_PASSWORD')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:SOC_ANSIBLE_CONFIG = @{
        subscription_id = 'test-subscription'
        resource_group = 'test-rg'
        linux_vm = 'test-linux'
        windows_vm = 'test-windows'
    } | ConvertTo-Json -Compress
    $env:SOC_ANSIBLE_PRIVATE_KEY = 'TEST-PRIVATE-KEY'
    $env:SOC_DSRM_PASSWORD = 'TEST-DSRM'
    $launcher = Join-Path (Split-Path $PSScriptRoot) 'Invoke-Ansible.ps1'
    & $launcher
    if ($global:SocLauncherTestState.RunnerCalls -ne 1 -or $global:SocLauncherTestState.AzureCalls -ne 2) {
        throw 'Launcher did not execute the expected operations.'
    }
    $global:SocLauncherTestState.RunnerExitCode = 2
    $failed = $false
    try { & $launcher }
    catch {
        if ($_.Exception.Message -notlike 'Ansible failed with exit code 2*') { throw }
        $failed = $true
    }
    if (!$failed) { throw 'Launcher swallowed the Ansible failure.' }
    Write-Output 'PowerShell launcher: JSON transport, paths with spaces, and error propagation verified (offline mock).'
}
finally {
    foreach ($name in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
    Remove-Variable -Name SocLauncherTestState -Scope Global
}
