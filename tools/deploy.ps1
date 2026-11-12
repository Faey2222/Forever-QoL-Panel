# Links the addon into the WoW: Forever client as "ForeverQoLPanel_Dev", so every change is live after
# /reload and addon managers never mistake the test copy for the released addon.
# Usage: powershell -File tools/deploy.ps1 [-AddOnsDir <path>] [-Copy]
param(
    [string[]]$AddOnsDir = @("G:\Battle.net\World of Warcraft\_forever_\Interface\AddOns"),
    [switch]$Copy
)
$ErrorActionPreference = "Stop"
$name = "ForeverQoLPanel_Dev"
$source = Join-Path $PSScriptRoot "..\ForeverQoLPanel" | Resolve-Path

# WoW loads the TOC named like the folder. The dev TOC is generated and never committed.
$toc = Get-Content (Join-Path $source "ForeverQoLPanel.toc") -Encoding UTF8
$toc = $toc -replace '^## Title: .*$', '## Title: Forever QoL Panel |cffff8000(Dev)|r' -replace 'AddOns\\ForeverQoLPanel\\', "AddOns\$name\"
[System.IO.File]::WriteAllLines((Join-Path $source "$name.toc"), $toc, (New-Object System.Text.UTF8Encoding($false)))

foreach ($dir in $AddOnsDir) {
    if (-not (Test-Path $dir)) {
        Write-Host "Skipped (not installed): $dir"
        continue
    }
    $target = Join-Path $dir $name
    if (Test-Path $target) {
        $item = Get-Item $target -Force
        if ($item.LinkType -eq "Junction" -and -not $Copy) {
            Write-Host "Already linked: $target -> $($item.Target)"
            continue
        }
        if ($item.LinkType) { cmd /c rmdir "$target" } else { Remove-Item $target -Recurse -Force }
    }
    if ($Copy) {
        Copy-Item $source $target -Recurse
        Write-Host "Copied to $target"
    } else {
        New-Item -ItemType Junction -Path $target -Target $source | Out-Null
        Write-Host "Linked $target -> $source"
    }
}
