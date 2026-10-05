#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Library (dot-source it): reads and writes the policy files of .octopus/policies and extracts their Rego for opa.

.DESCRIPTION
    A policy file (https://octopus.com/docs/platform-hub/policies/examples#writing-policies-as-ocl-files) holds the
    attributes name, description, violation_action and violation_reason, and two blocks, conditions and scope, each
    with one indented heredoc attribute rego. Both Rego modules declare the package named like the file (the slug).

      Read-PolicyOcl     Parses one policy file. The Rego is unindented the way Octopus's OCL parser does it.
      Format-PolicyOcl   The canonical text of a policy: the attribute order and heredoc indentation of the files the
                         Octopus UI writes (OctopusDeploy/Ocl, source/Ocl/OclWriter.cs), so a later edit in the UI
                         changes only what it edits.
      Export-PolicyRego  Writes build/rego/<slug>/conditions.rego and scope.rego for every policy.

    Octopus's parser (OctopusDeploy/Ocl, source/Ocl/Parsing/HeredocParser.cs, method Unindent) removes from each line
    of an indented heredoc (<<-EOT) the smaller of two counts: the closing tag's indentation, and the least
    indentation of a line that is not blank. A space and a tab count one character each. The CI job runs that parser
    (tools/ocl-check) and compares what it reads with build/rego.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PolicyRepoRoot = Split-Path -Parent $PSScriptRoot
# The order of the Octopus UI's writer: attributes first, then the blocks conditions and scope.
$script:PolicyAttributes = @('name', 'description', 'violation_action', 'violation_reason')
$script:PolicyBlocks = @('conditions', 'scope')
$script:HeredocIndent = ' ' * 12

function Get-LeadingWhitespaceCount {
    param([string] $Line)
    for ($index = 0; $index -lt $Line.Length; $index++) {
        if (-not [char]::IsWhiteSpace($Line[$index])) { return $index }
    }
    return [int]::MaxValue
}

function ConvertFrom-IndentedHeredoc {
    # The value of an indented heredoc, as Octopus reads it: lines joined by LF, no final line break.
    param([string[]] $Lines, [string] $EndLine)
    if ($Lines.Count -eq 0) { return '' }
    $unindentBy = Get-LeadingWhitespaceCount $EndLine
    foreach ($line in $Lines) { $unindentBy = [Math]::Min($unindentBy, (Get-LeadingWhitespaceCount $line)) }
    $unindented = foreach ($line in $Lines) { if ($line.Length -le $unindentBy) { '' } else { $line.Substring($unindentBy) } }
    return (@($unindented) -join "`n")
}

function Read-PolicyOcl {
    param([Parameter(Mandatory)] [string] $Path)

    $slug = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($slug -cnotmatch '^[a-z][a-z0-9_]*$') {
        throw "${Path}: the file name is the policy's slug and Rego package: lowercase letters, digits and underscores, no dashes."
    }
    $text = [IO.File]::ReadAllText($Path)
    if ($text.Contains("`r")) { throw "${Path}: use LF line endings." }
    $lines = @($text.TrimEnd("`n") -split "`n")
    $attributes = [ordered]@{}
    $rego = [ordered]@{}

    $index = 0
    while ($index -lt $lines.Count) {
        $line = $lines[$index]
        $where = "${Path}:$($index + 1)"
        if ($line -match '^\s*$') { $index++; continue }

        if ($line -cmatch '^([a-z_]+) = "([^"\\]*)"$') {
            $name = $Matches[1]
            if ($script:PolicyAttributes -cnotcontains $name) { throw "${where}: unknown attribute $name (expected $($script:PolicyAttributes -join ', '))." }
            if ($attributes.Contains($name)) { throw "${where}: attribute $name appears twice." }
            $attributes[$name] = $Matches[2]
            $index++
            continue
        }

        if ($line -cmatch '^([a-z_]+) \{$') {
            $block = $Matches[1]
            if ($script:PolicyBlocks -cnotcontains $block) { throw "${where}: unknown block $block (expected conditions and scope)." }
            if ($rego.Contains($block)) { throw "${where}: block $block appears twice." }
            $index++
            if ($index -ge $lines.Count -or $lines[$index] -cnotmatch '^\s+rego = <<-([A-Za-z_]+)$') {
                throw "${Path}:$($index + 1): block $block holds one attribute, rego = <<-EOT (an indented heredoc)."
            }
            $tag = [regex]::Match($lines[$index], '<<-([A-Za-z_]+)$').Groups[1].Value
            $index++
            $body = [Collections.Generic.List[string]]::new()
            while ($index -lt $lines.Count -and $lines[$index] -cnotmatch "^\s*$([regex]::Escape($tag))\s*$") {
                $body.Add($lines[$index])
                $index++
            }
            if ($index -ge $lines.Count) { throw "${where}: the heredoc of block $block has no closing $tag." }
            $endLine = $lines[$index]
            $index++
            if ($index -ge $lines.Count -or $lines[$index] -cne '}') { throw "${Path}:$($index + 1): block $block ends with } after its heredoc." }
            $index++
            $rego[$block] = ConvertFrom-IndentedHeredoc -Lines $body.ToArray() -EndLine $endLine
            continue
        }

        throw "${where}: not a policy attribute or block: $line"
    }

    foreach ($required in 'name', 'violation_action') {
        if (-not $attributes.Contains($required)) { throw "${Path}: attribute $required is required." }
    }
    if (@('warn', 'block') -cnotcontains $attributes['violation_action']) { throw "${Path}: violation_action is warn or block." }
    foreach ($block in $script:PolicyBlocks) {
        if (-not $rego.Contains($block)) { throw "${Path}: block $block is required." }
        $package = [regex]::Match($rego[$block], '(?m)^package (\S+)$')
        if (-not $package.Success -or $package.Groups[1].Value -cne $slug) {
            throw "${Path}: the $block Rego declares package $slug, the file's name."
        }
    }
    [pscustomobject]@{ Path = $Path; Slug = $slug; Attributes = $attributes; Rego = $rego }
}

function Format-PolicyOcl {
    # The canonical file text of a policy; -Rego replaces the Rego of a block (conditions or scope).
    param([Parameter(Mandatory)] $Policy, [hashtable] $Rego = @{})
    $text = [Text.StringBuilder]::new()
    foreach ($name in $script:PolicyAttributes) {
        if (-not $Policy.Attributes.Contains($name)) { continue }
        $value = [string] $Policy.Attributes[$name]
        if ($value -match '["\\\n]') { throw "$($Policy.Path): attribute $name may not hold a quote, a backslash or a line break." }
        [void] $text.Append("$name = `"$value`"`n")
    }
    foreach ($block in $script:PolicyBlocks) {
        $value = if ($Rego.ContainsKey($block)) { $Rego[$block] } else { $Policy.Rego[$block] }
        [void] $text.Append("`n$block {`n    rego = <<-EOT`n")
        foreach ($line in ($value.TrimEnd("`n") -split "`n")) {
            [void] $text.Append($(if ($line.Length -eq 0) { "`n" } else { "$($script:HeredocIndent)$line`n" }))
        }
        [void] $text.Append("$($script:HeredocIndent)EOT`n}`n")
    }
    return $text.ToString()
}

function Export-PolicyRego {
    # Writes build/rego/<slug>/conditions.rego and scope.rego for every policy file, and returns the parsed policies.
    param(
        [string] $Root = $script:PolicyRepoRoot,
        [string] $Destination = (Join-Path $script:PolicyRepoRoot 'build' 'rego')
    )
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root '.octopus' 'policies') -Filter '*.ocl' -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No policy files in $(Join-Path $Root '.octopus' 'policies')." }
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    foreach ($file in $files) {
        $policy = Read-PolicyOcl -Path $file.FullName
        $folder = Join-Path $Destination $policy.Slug
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        foreach ($block in $script:PolicyBlocks) {
            [IO.File]::WriteAllText((Join-Path $folder "$block.rego"), "$($policy.Rego[$block])`n")
        }
        $policy
    }
}
