#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Builds fixtures/: the policy input of real deployments, read from Octopus with GET requests only.

.DESCRIPTION
    Run by the operator (ai-ops) on the operator's machine, never in CI. The Octopus key stays with the
    demo-environment kit: this script dot-sources the kit's demo-common.ps1 and calls Invoke-OctopusApi, always with
    -Method Get. The fixtures hold names, IDs, slugs, action types and flags: no variable value, no step property
    value, no secret.

    For each space, the most recent deployment of each project to the environment prod, each deployment to another
    environment (-OtherEnvironment) and each out-of-scope case (-OutOfScope) becomes
    fixtures/<space slug>/<project slug>.<environment slug>.json: the policy input that
    https://octopus.com/docs/platform-hub/policies/schema documents, checked against schema/policy-input.schema.json
    (the JSON schema of that page). fixtures/manifest.json lists every fixture with its deployment, release, task state
    and process source, and the projects that have no such deployment.

    The process is the one the deployment ran, skipped steps included (a skipped step stays in Steps, and its ID is in
    SkippedSteps):
      - a database-stored project: the release's snapshot, the deployment's DeploymentProcessId;
      - a version-controlled project: the process at the release's Git commit, which must match that snapshot.

    README.md ("How the fixtures are built") records the choices where the documentation leaves a field open.

.EXAMPLE
    sudo -n -u aiops -H bash -lc 'cd ~/work/platform-hub/octopus-platform-hub && pwsh -NoProfile -File scripts/build-fixtures.ps1'
#>
[CmdletBinding()]
param(
    # The demo-environment kit's library (Read-DemoConfig, Invoke-OctopusApi) and a demo file that names the instance.
    [string] $DemoCommon = (Join-Path $HOME 'demo-environment-kit' '.claude' 'skills' 'demo-environment' 'scripts' 'demo-common.ps1'),
    [string] $DemoFile = (Join-Path $HOME 'demo-environment-kit' 'fleet' 'systems' 'cmdemo1.json'),
    # The spaces: cmdemo1 demo, cmdemo2 demo, cmdemo3 demo, the fleet's systems whose space has another name
    # (cmfleet; "JeffreyPalermo - Sites" of jpcom; biblefleet and "Adam and woman in the garden of Eden" of adameve, the
    # two spaces of the Bible fleet), and the bootcamp's ChurchBulletin.
    [string[]] $SpaceId = @('Spaces-355', 'Spaces-356', 'Spaces-357', 'Spaces-378', 'Spaces-375', 'Spaces-396', 'Spaces-395', 'Spaces-315'),
    [string] $Environment = 'prod',
    # Deployments to another environment, each <space id>/<project slug>/<environment slug>: the latest deployment
    # there. The two health check policies apply to every environment, and adameve has no environment prod yet.
    [string[]] $OtherEnvironment = @(
        'Spaces-396/biblefleet-dashboard/tdd', 'Spaces-396/biblefleet-dashboard/uat',
        'Spaces-395/adameve-system/tdd', 'Spaces-395/adameve-web/tdd'
    ),
    # Out-of-scope cases, each <space id>/<project slug>/<environment slug>: the latest deployment there.
    [string[]] $OutOfScope = @('Spaces-355/cmdemo1-ui/tdd'),
    [string] $Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures')
)

. $DemoCommon
$config = Read-DemoConfig -Path $DemoFile
$root = Split-Path -Parent $PSScriptRoot
$schema = [IO.File]::ReadAllText((Join-Path $root 'schema' 'policy-input.schema.json'))
$cache = @{}

function Get-Octopus {
    # Every Octopus call of this script: a GET.
    param([Parameter(Mandatory)] [string] $Path)
    Invoke-OctopusApi -Config $config -Path $Path -Method Get
}

function Get-Cached {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not $cache.ContainsKey($Path)) { $cache[$Path] = Get-Octopus $Path }
    return $cache[$Path]
}

function Get-Value {
    # A property that may be missing (strict mode), or $Default.
    param($Object, [string] $Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-Array {
    # A property as an array (empty when missing), not unrolled.
    param($Object, [string] $Name)
    $value = Get-Value $Object $Name
    if ($null -eq $value) { return , @() }
    return , @($value)
}

function ConvertTo-Rfc3339 {
    param($Value)
    $date = if ($Value -is [datetime]) { $Value.ToUniversalTime() } else { [DateTimeOffset]::Parse([string] $Value, [cultureinfo]::InvariantCulture).UtcDateTime }
    return $date.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [cultureinfo]::InvariantCulture)
}

function Get-StatusCode {
    param($ErrorRecord)
    $response = Get-Value $ErrorRecord.Exception 'Response'
    $status = Get-Value $response 'StatusCode'
    if ($null -eq $status) { return 0 }
    return [int] $status
}

function Get-FeedInput {
    # The Feed object of a package, or $null when the operator may not read the feed (FeedView).
    param([string] $Space, [string] $FeedId)
    $path = "/api/$Space/feeds/$FeedId"
    if (-not $cache.ContainsKey($path)) {
        try { $cache[$path] = Get-Octopus $path }
        catch {
            if ((Get-StatusCode $_) -in 401, 403) { $cache[$path] = $null } else { throw }
        }
    }
    $feed = $cache[$path]
    if ($null -eq $feed) { return $null }
    $object = [ordered]@{ Id = $feed.Id; Name = $feed.Name; Slug = $feed.Slug; Type = $feed.FeedType; Source = 'Space' }
    $uri = [string] (Get-Value $feed 'FeedUri' '')
    if ($uri) { $object.Uri = $uri }
    return $object
}

function Get-ActorInput {
    # Who started the deployment. A person's username is replaced (the repository is public); service accounts keep
    # their names.
    param($Deployment, $Notes)
    $id = [string] $Deployment.DeployedById
    $user = $null
    try { $user = Get-Cached "/api/users/$id" } catch { $user = $null }
    $isService = $null -ne $user -and [bool] (Get-Value $user 'IsService' $false)
    if (-not $isService) { $Notes.Add('Actor.Username of a person replaced by redacted-person.') }
    return [ordered]@{
        Id       = $id
        Username = $(if ($isService) { [string] $Deployment.DeployedBy } else { 'redacted-person' })
        Type     = [string] (Get-Value $Deployment 'DeployedByActorType' 'Unknown')
    }
}

function Get-ProcessShape {
    # What the policy input reads from a process, to compare the Git commit's process with the release's snapshot.
    param($Process)
    $steps = foreach ($step in @($Process.Steps)) {
        [ordered]@{
            Id           = $step.Id
            Slug         = $step.Slug
            Condition    = $step.Condition
            StartTrigger = $step.StartTrigger
            Actions      = @(foreach ($action in @($step.Actions)) {
                    [ordered]@{
                        Id                   = $action.Id
                        Slug                 = $action.Slug
                        ActionType           = $action.ActionType
                        IsDisabled           = $action.IsDisabled
                        IsRequired           = $action.IsRequired
                        Environments         = Get-Array $action 'Environments'
                        ExcludedEnvironments = Get-Array $action 'ExcludedEnvironments'
                        Channels             = Get-Array $action 'Channels'
                        TenantTags           = Get-Array $action 'TenantTags'
                        Packages             = @(foreach ($package in (Get-Array $action 'Packages')) { "$($package.Id)|$($package.PackageId)|$($package.FeedId)" })
                    }
                })
        }
    }
    return (ConvertTo-Json -InputObject @($steps) -Depth 10 -Compress)
}

function Test-Conditional {
    # IsConditional: "the step has non-default run conditions" (schema page). Read broadly, as the best-practices page
    # describes them: a run condition other than Success, or a scope by environment, channel or tenant tag.
    param($Step, $Action)
    if ([string] $Step.Condition -ne 'Success') { return $true }
    $actionCondition = [string] (Get-Value $Action 'Condition' 'Success')
    if ($actionCondition -and $actionCondition -ne 'Success') { return $true }
    foreach ($name in 'Environments', 'ExcludedEnvironments', 'Channels', 'TenantTags') {
        if ((Get-Array $Action $name).Count -gt 0) { return $true }
    }
    foreach ($name in 'EnvironmentsVariable', 'ExcludedEnvironmentsVariable', 'ChannelsVariable', 'TenantTagsVariable') {
        if ([string] (Get-Value $Action $name '')) { return $true }
    }
    return $false
}

function ConvertTo-StepsInput {
    # Steps (one per action, in process order) and Execution (one group per step) of the policy input.
    param($Process, $Release, [string] $Space, $Notes)
    $steps = [Collections.Generic.List[object]]::new()
    $execution = [Collections.Generic.List[object]]::new()
    foreach ($step in @($Process.Steps)) {
        $ids = [Collections.Generic.List[string]]::new()
        foreach ($action in @($step.Actions)) {
            $ids.Add([string] $action.Id)
            $properties = Get-Value $action 'Properties'
            $source = [ordered]@{ Type = ''; SlugOrId = '' }
            if ($action.ActionType -eq 'Octopus.ProcessTemplate') {
                $source = [ordered]@{ Type = 'Process Template'; SlugOrId = [string] (Get-Value $properties 'Octopus.Action.ProcessTemplate.Reference.Slug' '') }
                $mask = [string] (Get-Value $properties 'Octopus.Action.ProcessTemplate.Reference.VersionMask' '')
                if ($mask) { $source.Version = $mask }
                $Notes.Add("Step $($action.Slug) uses a process template: one step with the usage's version mask; Octopus lists the template's own steps.")
            }
            elseif ([string] (Get-Value $properties 'Octopus.Action.Template.Id' '')) {
                $source = [ordered]@{ Type = 'Step Template'; SlugOrId = [string] (Get-Value $properties 'Octopus.Action.Template.Id') }
                $version = [string] (Get-Value $properties 'Octopus.Action.Template.Version' '')
                if ($version) { $source.Version = $version }
            }
            $packages = [Collections.Generic.List[object]]::new()
            foreach ($package in (Get-Array $action 'Packages')) {
                $entry = [ordered]@{ Id = [string] $package.Id; Name = [string] $package.PackageId }
                $selected = @((Get-Array $Release 'SelectedPackages') | Where-Object {
                        $_.ActionName -eq $action.Name -and [string] (Get-Value $_ 'PackageReferenceName' '') -eq [string] (Get-Value $package 'Name' '')
                    }) | Select-Object -First 1
                if ($selected) { $entry.Version = [string] $selected.Version }
                $feed = Get-FeedInput -Space $Space -FeedId ([string] $package.FeedId)
                if ($feed) { $entry.Feed = $feed }
                else { $Notes.Add("Feed $($package.FeedId) of package $($package.PackageId) is not readable for the operator (FeedView): Feed left out.") }
                $packages.Add($entry)
            }
            $steps.Add([ordered]@{
                    Id            = [string] $action.Id
                    Slug          = [string] $action.Slug
                    ActionType    = [string] $action.ActionType
                    Enabled       = -not [bool] $action.IsDisabled
                    IsRequired    = [bool] $action.IsRequired
                    IsConditional = Test-Conditional -Step $step -Action $action
                    Source        = $source
                    Packages      = $packages.ToArray()
                })
        }
        $execution.Add([ordered]@{ StartTrigger = [string] $step.StartTrigger; Steps = $ids.ToArray() })
    }
    return [pscustomobject]@{ Steps = $steps.ToArray(); Execution = $execution.ToArray() }
}

function Get-SystemName {
    param($Space)
    if ($Space.Slug -like '*-demo') { return $Space.Slug.Substring(0, $Space.Slug.Length - '-demo'.Length) }
    if ($Space.Slug -eq 'churchbulletin') { return 'bootcamp' }
    if ($Space.Slug -eq 'jeffreypalermo-sites') { return 'jpcom' }
    if ($Space.Slug -eq 'adam-and-woman-in-the-garden-of-eden') { return 'adameve' }
    return $Space.Slug
}

function New-Fixture {
    param($Case)
    $spaceId = $Case.SpaceId
    $space = Get-Cached "/api/spaces/$spaceId"
    $system = Get-SystemName $space
    $project = @(Get-Cached "/api/$spaceId/projects/all") | Where-Object Slug -eq $Case.Project | Select-Object -First 1
    if (-not $project) { throw "No project $($Case.Project) in $spaceId." }
    $missing = [ordered]@{ system = $system; space = "$($space.Name) ($spaceId)"; project = $project.Name; environment = $Case.Environment; purpose = $Case.Purpose }
    $environment = @(Get-Cached "/api/$spaceId/environments/all") | Where-Object Slug -eq $Case.Environment | Select-Object -First 1
    if (-not $environment) { $missing.note = "the space has no environment $($Case.Environment)"; return [pscustomobject]@{ Missing = $missing } }
    $deployment = @((Get-Octopus "/api/$spaceId/deployments?projects=$($project.Id)&environments=$($environment.Id)&take=1").Items) | Select-Object -First 1
    if (-not $deployment) { $missing.note = "no deployment to $($environment.Name)"; return [pscustomobject]@{ Missing = $missing } }

    $notes = [Collections.Generic.List[string]]::new()
    $release = Get-Octopus "/api/$spaceId/releases/$($deployment.ReleaseId)"
    $task = Get-Octopus "/api/tasks/$($deployment.TaskId)"
    $group = @(Get-Cached "/api/$spaceId/projectgroups/all") | Where-Object Id -eq $project.ProjectGroupId | Select-Object -First 1
    foreach ($owner in $project, $environment) {
        if (Get-Value $owner 'ExtensionSettings') {
            throw "$($owner.Id) has extension settings (ITSM change control?): derive RequiresApproval from them before building its fixture."
        }
    }

    $snapshot = Get-Octopus "/api/$spaceId/deploymentprocesses/$($deployment.DeploymentProcessId)"
    if ($project.IsVersionControlled) {
        $commit = [string] $release.VersionControlReference.GitCommit
        $process = Get-Octopus "/api/$spaceId/projects/$($project.Id)/$commit/deploymentprocesses"
        if ((Get-ProcessShape $process) -cne (Get-ProcessShape $snapshot)) {
            throw "$($project.Name) $($release.Version): the process at Git commit $commit differs from the release's snapshot $($deployment.DeploymentProcessId); check which one the deployment ran."
        }
        $processSource = "Git commit $commit of $($release.VersionControlReference.GitRef) (equal to the snapshot $($deployment.DeploymentProcessId))"
    }
    else {
        $process = $snapshot
        $processSource = "release snapshot $($deployment.DeploymentProcessId)"
    }
    $converted = ConvertTo-StepsInput -Process $process -Release $release -Space $spaceId -Notes $notes

    $policyInput = [ordered]@{
        Environment      = [ordered]@{ Id = $environment.Id; Name = $environment.Name; Slug = $environment.Slug; Tags = Get-Array $environment 'EnvironmentTags' }
        Project          = [ordered]@{ Id = $project.Id; Name = $project.Name; Slug = $project.Slug; Tags = Get-Array $project 'ProjectTags' }
        Space            = [ordered]@{ Id = $space.Id; Name = $space.Name; Slug = $space.Slug }
        ProjectGroup     = [ordered]@{ Id = $group.Id; Name = $group.Name; Slug = $group.Slug }
        Steps            = $converted.Steps
        SkippedSteps     = [string[]] (Get-Array $deployment 'SkipActions')
        Execution        = $converted.Execution
        RequiresApproval = $false
        Actor            = Get-ActorInput -Deployment $deployment -Notes $notes
        CreatedAt        = ConvertTo-Rfc3339 $deployment.Created
    }
    $tenantId = [string] (Get-Value $deployment 'TenantId' '')
    if ($tenantId) {
        $tenant = Get-Octopus "/api/$spaceId/tenants/$tenantId"
        $policyInput.Tenant = [ordered]@{ Id = $tenant.Id; Name = $tenant.Name; Slug = $tenant.Slug; Tags = Get-Array $tenant 'TenantTags' }
    }
    # A release has a version and no other name: Name is the version.
    $policyInput.Release = [ordered]@{ Id = $release.Id; Name = $release.Version; Version = $release.Version }
    if ($project.IsVersionControlled) { $policyInput.Release.GitRef = [string] $release.VersionControlReference.GitRef }

    $json = ConvertTo-Json -InputObject $policyInput -Depth 20
    $problems = $null
    if (-not (Test-Json -Json $json -Schema $schema -ErrorAction SilentlyContinue -ErrorVariable problems)) {
        throw "$($project.Name) $($Case.Environment): the input does not match schema/policy-input.schema.json: $($problems -join '; ')"
    }
    $file = "$($space.Slug)/$($project.Slug).$($environment.Slug).json"
    return [pscustomobject]@{
        File  = $file
        Json  = $json
        Entry = [ordered]@{
            file        = $file
            system      = $system
            space       = "$($space.Name) ($spaceId)"
            project     = $project.Name
            environment = $environment.Name
            purpose     = $Case.Purpose
            deployment  = $deployment.Id
            release     = $release.Version
            created     = $policyInput.CreatedAt
            taskState   = [string] $task.State
            actorType   = $policyInput.Actor.Type
            process     = $processSource
            notes       = $notes.ToArray()
        }
    }
}

$cases = [Collections.Generic.List[object]]::new()
foreach ($space in $SpaceId) {
    foreach ($project in @(Get-Cached "/api/$space/projects/all") | Sort-Object Slug) {
        $cases.Add([pscustomobject]@{ SpaceId = $space; Project = $project.Slug; Environment = $Environment; Purpose = "latest $Environment deployment" })
    }
}
foreach ($case in $OtherEnvironment) {
    $parts = $case -split '/'
    if ($parts.Count -ne 3) { throw "-OtherEnvironment '$case': <space id>/<project slug>/<environment slug>." }
    $cases.Add([pscustomobject]@{ SpaceId = $parts[0]; Project = $parts[1]; Environment = $parts[2]; Purpose = "latest $($parts[2]) deployment" })
}
foreach ($case in $OutOfScope) {
    $parts = $case -split '/'
    if ($parts.Count -ne 3) { throw "-OutOfScope '$case': <space id>/<project slug>/<environment slug>." }
    $cases.Add([pscustomobject]@{ SpaceId = $parts[0]; Project = $parts[1]; Environment = $parts[2]; Purpose = "out-of-scope case: latest $($parts[2]) deployment" })
}

# Build everything first; write only when every fixture is valid.
$built = foreach ($case in $cases) {
    Write-Host "==> $($case.SpaceId) $($case.Project) $($case.Environment)"
    New-Fixture -Case $case
}
$fixtures = @($built | Where-Object { $_.PSObject.Properties['File'] })
$missing = @($built | Where-Object { $_.PSObject.Properties['Missing'] } | ForEach-Object Missing)

if (Test-Path -LiteralPath $Output) {
    Get-ChildItem -LiteralPath $Output -Recurse -File -Filter '*.json' | Remove-Item -Force
}
foreach ($fixture in $fixtures) {
    $path = Join-Path $Output $fixture.File
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, "$($fixture.Json)`n")
    Write-Host "PASS fixtures/$($fixture.File): $($fixture.Entry.deployment), release $($fixture.Entry.release), $($fixture.Entry.process)"
}
foreach ($entry in $missing) { Write-Host "SKIP $($entry.space) $($entry.project) $($entry.environment): $($entry.note)" }

$manifest = [ordered]@{
    generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    instance  = $config.octopus.url
    server    = [string] (Get-Octopus '/api').Version
    schema    = 'schema/policy-input.schema.json'
    fixtures  = @($fixtures | ForEach-Object Entry)
    missing   = $missing
}
[IO.File]::WriteAllText((Join-Path $Output 'manifest.json'), "$(ConvertTo-Json -InputObject $manifest -Depth 10)`n")
Write-Host "PASS fixtures/manifest.json: $($fixtures.Count) fixtures, $($missing.Count) without a deployment"
