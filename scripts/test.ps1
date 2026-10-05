#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    The policy checks: the Rego of .octopus/policies and tests/ passes opa fmt, opa check --strict and opa test.

.DESCRIPTION
    Extracts each policy's conditions and scope Rego to build/rego/<slug>/ (scripts/policies.ps1), then checks:
      - opa fmt: the Rego in the policy files and the tests are formatted;
      - layout: each policy file is in the canonical layout of the Octopus UI's writer;
      - opa check --strict over build/rego and tests;
      - opa test over build/rego and tests.
    The CI workflow check.yml runs it on every pull request and on main.

.PARAMETER Fix
    Formats first: opa fmt over the extracted Rego and the tests, and each policy file rewritten in the canonical
    layout with its formatted Rego.

.PARAMETER Opa
    The opa executable (default: opa on PATH; check.yml installs the version it pins, with its checksum).
#>
[CmdletBinding()]
param(
    [switch] $Fix,
    [string] $Opa = 'opa'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. (Join-Path $PSScriptRoot 'policies.ps1')
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build' 'rego'
$tests = Join-Path $root 'tests'
$failures = 0

$policies = @(Export-PolicyRego -Root $root -Destination $build)
if ($Fix) {
    & $Opa fmt --write $build $tests | Out-Null
    foreach ($policy in $policies) {
        $rego = @{}
        foreach ($block in 'conditions', 'scope') { $rego[$block] = [IO.File]::ReadAllText((Join-Path $build $policy.Slug "$block.rego")) }
        [IO.File]::WriteAllText($policy.Path, (Format-PolicyOcl -Policy $policy -Rego $rego))
    }
    $policies = @(Export-PolicyRego -Root $root -Destination $build)
}

Write-Host "==> opa fmt"
$unformatted = @(& $Opa fmt --list $build $tests | Where-Object { $_ })
if ($unformatted.Count -gt 0) {
    $failures++
    foreach ($file in $unformatted) {
        Write-Host "FAIL $([IO.Path]::GetRelativePath($root, $file)) is not formatted (run scripts/test.ps1 -Fix):"
        & $Opa fmt --diff $file | Write-Host
    }
}
else { Write-Host "PASS the Rego of $($policies.Count) policies and of tests/ is formatted" }

Write-Host "==> layout"
foreach ($policy in $policies) {
    $relative = [IO.Path]::GetRelativePath($root, $policy.Path)
    if ((Format-PolicyOcl -Policy $policy) -cne [IO.File]::ReadAllText($policy.Path)) {
        $failures++
        Write-Host "FAIL $relative is not in the canonical layout (run scripts/test.ps1 -Fix)"
    }
    else { Write-Host "PASS $relative" }
}

Write-Host "==> opa check --strict"
& $Opa check --strict $build $tests
Write-Host "PASS opa check --strict"

Write-Host "==> opa test"
& $Opa test $build $tests --verbose

if ($failures -gt 0) { throw "$failures check(s) failed." }
Write-Host "PASS every policy check"
