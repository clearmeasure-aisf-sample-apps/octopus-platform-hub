# Octopus Platform Hub repository

The [Platform Hub](https://octopus.com/docs/platform-hub) repository of the Octopus instance
https://clearmeasure.octopus.app. Platform Hub reads one Git repository for the whole instance; this repository is the
only source of the instance's process templates and policies (decision D2 of the Platform Hub plan).

**Status: connected since 2026-10-07; both policies active in warn mode.**

- **Version control.** Platform Hub reads this repository at `main`, base path `.octopus`, with the default branch
  protected and **no credentials**: the repository is public, so Octopus only reads. Nothing can be saved from the
  Octopus UI; a policy or a template changes here, by pull request. That is the decision (Jeffrey, 2026-10-07):
  no edits from the Octopus UI, so no Platform Hub GitHub App connection is made.
- **Policies.** `prod_has_sign_off` and `prod_db_change_has_restore_point` are published as 1.0.0 (commit `34d1224`)
  and active. Both warn and block nothing.
- **Seen at work** in a throwaway space (`cmprobe demo`, deleted afterwards), four prod deployments:

  | Process | Sign-off policy | Restore-point policy | Task |
  |---|---|---|---|
  | Sign-off, Record restore point, Migrate database | compliant | compliant | Success, no warning |
  | Sign-off, Update deployable | compliant | compliant ("No database change runs in this deployment.", at Info level) | Success, no warning |
  | Migrate database only | warning with the policy's reason | warning with the policy's reason | Success with warnings; the deployment went on |
  | Sign-off and Record restore point scoped to uat only, Migrate database | compliant | compliant | Success, no warning: **see the limit below** |

- **The limit Octopus has.** `input.Steps` lists every step of the process, also a step whose environment scope
  leaves this deployment out; such a step has `Enabled: true` and `IsConditional: true`, exactly like a step scoped to
  include it. A policy cannot tell a sign-off that runs in prod from one scoped away from it. The demo-environment
  kit's fleet reads the process with its scopes and reports that case (`policy/<slug>/<project>/sign-off` and
  `.../restore-point` of `test-fleet.ps1`); the policies here catch what the fleet cannot see, a step disabled or
  skipped in one deployment. Both stay.
- **Not done:** the process template `cmdemo-process-template` is still a draft and shared with no space;
  [How it gets connected](#how-it-gets-connected) keeps the remaining steps.

## What it serves

| System | Space | Policies | Templates |
|---|---|---|---|
| cmdemo1 | `cmdemo1 demo` (Spaces-355, slug `cmdemo1-demo`) | both | `cmdemo-process-template` once the kit uses it (plan phase 4) |
| cmdemo2 | `cmdemo2 demo` (Spaces-356, slug `cmdemo2-demo`) | both | the same |
| cmdemo3 | `cmdemo3 demo` (Spaces-357, slug `cmdemo3-demo`) | both | the same |
| bootcamp | `ChurchBulletin` (Spaces-315, slug `churchbulletin`), project `ChurchBulletin-gh` | both; exempt from the sign-off | only if its owners adopt them (D6) |

The policies apply to every space whose slug ends in `-demo` (the demo-environment kit names each space
`<slug> demo`), so a new demo system joins with no change here, and to `churchbulletin`. No other space of the
instance is in their scope.

## Layout

```text
.octopus/                                Platform Hub's base path (Version Control settings)
  policies/
    prod_has_sign_off.ocl                policy, warn mode
    prod_db_change_has_restore_point.ocl policy, warn mode
  process-templates/
    cmdemo-process-template.ocl          process template, DRAFT
fixtures/                                the policy input of real deployments, and manifest.json
schema/policy-input.schema.json          the documented policy input schema, verbatim
scripts/                                 test.ps1, preview.ps1, build-fixtures.ps1; policies.ps1 is their library
tests/                                   OPA unit tests (*_test.rego) and their input builders (policy_input.rego)
tools/ocl-check/                         Octopus's OCL parser over every .ocl file (CI)
PREVIEW.md                               the compliance preview: every policy over every fixture
.github/workflows/check.yml              CI
```

Octopus reads only the base path, `.octopus`. The layout follows the documentation and Octopus's own samples:

- One repository, branch and base path for all of Platform Hub
  ([Platform Hub](https://octopus.com/docs/platform-hub); `BasePath` in the
  [version control API](https://octopus.com/docs/api/platform-hub)).
- Policies are OCL files in the `policies` folder. The file name is the policy's slug and the package of both Rego
  blocks, with no dashes; the file holds `name`, `description`, `violation_reason`, `violation_action`, and the blocks
  `scope` and `conditions`, each with a `rego` heredoc
  ([Policy examples: Writing policies as OCL files](https://octopus.com/docs/platform-hub/policies/examples#writing-policies-as-ocl-files),
  [Policies](https://octopus.com/docs/platform-hub/policies)).
- Process templates are `process-templates/<slug>.ocl`, project templates `project-templates/<slug>/`: the folders of
  [OctopusSamples/PlatformHubLibrary](https://github.com/OctopusSamples/PlatformHubLibrary) ("copy into
  `.octopus/policies`", "`.octopus/process-templates`") and of the sample Platform Hub repository
  [OctopusSolutionsEngineering/demo-platform-hub](https://github.com/OctopusSolutionsEngineering/demo-platform-hub)
  (commit c168634), whose OCL formats these files follow
  ([Process templates](https://octopus.com/docs/platform-hub/templates/process-templates),
  [Publishing and sharing](https://octopus.com/docs/platform-hub/templates/publishing-and-sharing),
  [Parameters](https://octopus.com/docs/platform-hub/templates/parameters)).
- The policy files are written in the layout of the Octopus UI's own writer (attribute order, `conditions` before
  `scope`, a heredoc indented by twelve spaces), so a later edit in the UI changes only what it edits.

## Policies

Both start in **warn** mode (D5): a violation lets the deployment run and is recorded in the task log, the project
dashboard and the audit log. The `-demo` spaces move to block after two clean weeks (plan phase 7), through a new
policy version.

| Policy | Rule | Exemption, with its reason (D5, 2026-10-05) |
|---|---|---|
| [`prod_has_sign_off`](.octopus/policies/prod_has_sign_off.ocl) "Deploy - Production has a sign-off" | A production deployment has a sign-off that runs: an enabled, not skipped step of type `Octopus.Manual`, or a step of the process template `cmdemo-process-template` | `churchbulletin`: the bootcamp has no Octopus approval by design; its master builds reach Prod after the TDD acceptance tests and the GitHub environment wait timers |
| [`prod_db_change_has_restore_point`](.octopus/policies/prod_db_change_has_restore_point.ocl) "Deploy - Production database change has a restore point" | A production deployment whose process changes a database schema (step `migrate-database`, the bootcamp's `run-db-migrations`, or a step of the template `kit-migrate-database`) records a restore point first (step `record-restore-point`, or the template `kit-record-restore-point`), finished before the first change | `cmdemo3-demo`: cmdemo3 runs SQL Server Express in its AKS cluster, which has no point-in-time restore |

- **Scope** (both): deployments, not runbook runs (`not input.Runbook`), to the environment `prod`, in a space whose
  slug ends in `-demo` or is `churchbulletin`.
- **Rego**: Rego v1, as the documentation's examples write it: the keywords `if`, `in` and `contains` with no import,
  the rules `evaluate` (scope) and `result` (conditions), and a result of the documented
  [output schema](https://octopus.com/docs/platform-hub/policies/schema#output-schema): `allowed`, `reason`, `action`.
  Every violation returns `"action": "warn"`.
- **Input fields used**, all from the [input schema](https://octopus.com/docs/platform-hub/policies/schema):
  `Space.Slug`, `Environment.Slug`, `Runbook` (absent for deployments), `Steps[].Id`, `.Slug`, `.ActionType`,
  `.Enabled`, `.Source.Type`, `.Source.SlugOrId`, `SkippedSteps` (step IDs) and `Execution[].StartTrigger`, `.Steps`.
  The input has no step name, so steps are matched by slug.
- **"Before"** means the restore point finishes before the first change starts: it comes earlier in the process, and an
  execution group after it, up to the change's, waits for the steps before it (`StartAfterPrevious`). A restore point
  that starts with the migration (`StartWithPrevious`) does not count.
- **An exemption** applies only when the rule fails. An exempt deployment is allowed, and its result's `reason` starts
  with `Exempt: `; a compliant deployment in an exempt space is simply allowed.

## Process templates

[`cmdemo-process-template`](.octopus/process-templates/cmdemo-process-template.ocl), "cmdemo-process-template": **DRAFT**, not published and used by
no project. It is the first template of plan section 5.2, for plan phase 4, and has to pass the spike of phase 2
first.

- One step, `sign-off` "Sign-off": a manual intervention (`Octopus.Manual`) whose responsible team is the `Teams`
  parameter `Template.SignOff.Teams`. A Teams parameter has no default, so each project sets its space's approvers team
  ([Parameters](https://octopus.com/docs/platform-hub/templates/parameters)).
- Its properties are those of the kit's Sign-off step today (`templates/system/octopus/projects.tf` and
  `templates/system-aks/octopus/projects.tf` of the demo-environment kit, and the live steps of cmdemo1, cmdemo2 and
  cmdemo3):

  | Property | Kit step today | Template |
  |---|---|---|
  | `Octopus.Action.Manual.Instructions` | `Sign off #{Octopus.Project.Name} #{Octopus.Release.Number} for #{Octopus.Environment.Name}: check the earlier environments, then Proceed with a note, or Abort.` | the same |
  | `Octopus.Action.Manual.ResponsibleTeamIds` | `local.sign_off_team_id`, the `<slug> approvers` team (D9) | `#{Template.SignOff.Teams}` |
  | `Octopus.Action.Manual.BlockConcurrentDeployments` | `False` | `False` |
  | `Octopus.Action.RunOnServer` | `false` | `false` |
  | Environments | `excluded_environments = [<first environment>]` | none: the usage step keeps `excluded_environments` (a template never decides where it runs, plan 5.1) |
  | Required | no (`IsRequired` false) | no; `prod_has_sign_off` flags a skipped sign-off |

- Its use in a kit project, by provider 1.20.0 (plan section 2; the exact version as a mask is spike item 2):

  ```hcl
  resource "octopusdeploy_process_step" "sign_off" {
    process_id            = octopusdeploy_process.deployable[each.key].id
    name                  = "Sign-off"
    type                  = "Octopus.ProcessTemplate"
    excluded_environments = [octopusdeploy_environment.this[local.first_environment].id]
    execution_properties = {
      "Octopus.Action.ProcessTemplate.Reference.Slug"        = "cmdemo-process-template"
      "Octopus.Action.ProcessTemplate.Reference.VersionMask" = local.system.octopus.templates["cmdemo-process-template"]
      "Template.SignOff.Teams"                               = local.sign_off_team_id
    }
  }
  ```

## Compliance preview

[PREVIEW.md](PREVIEW.md): both policies evaluated with `opa eval` over the fixtures, one row per system and project.
On 2026-10-05, the eight production deployments of cmdemo1, cmdemo2 and cmdemo3 comply with both policies; the
bootcamp is exempt from the sign-off and violates the restore-point rule (its step `run-db-migrations` changes the
Prod database with no restore point first). cmdemo3, once exempt from the restore point, has no exemption any
more: since cmdemo3-system #14 (2026-10-05) its step Record restore point takes a verified backup before every prod
deployment. Steps that change data but not the schema (Set employee middle names, Initialize database) do not count as
database changes (decision 2026-10-05).

## Fixtures

`scripts/build-fixtures.ps1` builds them; the operator runs it, with GET requests only. For each of the four spaces,
the most recent prod deployment of each project becomes `fixtures/<space slug>/<project slug>.prod.json`, and the
latest tdd deployment of cmdemo1-ui is the out-of-scope case. Each file is the policy input as documented, checked
against [schema/policy-input.schema.json](schema/policy-input.schema.json) (the JSON schema of the
[schema page](https://octopus.com/docs/platform-hub/policies/schema), docs commit 12eaec8, 2026-09-29).
[fixtures/manifest.json](fixtures/manifest.json) names each fixture's deployment, release, task state and process.
They hold names, IDs, slugs, action types and flags only: no variable or step property values.

The process is the one the deployment ran, skipped steps included: the release's snapshot (the deployment's
`DeploymentProcessId`) for a database-stored project; for the version-controlled `ChurchBulletin-gh`, the process at
the release's Git commit, which the script requires to equal the snapshot. Where the documentation leaves a field
open, the fixtures choose as follows; the licence day checks each against the Evaluations tab
([open questions](#open-questions-for-the-licence-day)):

| Field | From | Choice |
|---|---|---|
| `Steps` | each action of the process, in process order | every step, also those scoped to other environments ("all steps included in the deployment process") |
| `Steps[].IsConditional` | the step's run condition and the action's scope | true for a run condition other than Success, or a scope by environment, channel or tenant tag |
| `Steps[].Source` | `Octopus.Action.Template.Id` and `.Version`; a template usage's slug and mask | a built-in step gets `Type` and `SlugOrId` empty |
| `Steps[].Packages[]` | the action's packages, the release's selected versions, the space's feeds | `Name` is the package ID; no `GitRef` (no build information); `Feed` left out where the operator lacks FeedView (ChurchBulletin) |
| `Execution` | one group per step: its start trigger and its actions' IDs | |
| `RequiresApproval` | ITSM change control of project and environment | false: none is configured (the script stops if it finds extension settings) |
| `Actor` | `DeployedById`, `DeployedBy`, `DeployedByActorType` | a person's username is replaced by `redacted-person` (the repository is public) |
| `Release` | the release | `Name` is the version (a release has no other name); `GitRef` for the version-controlled project |

## Run the checks

PowerShell 7.4 or later, and `opa` 1.21.1 on the PATH (the static Linux binary of the
[v1.21.1 release](https://github.com/open-policy-agent/opa/releases/tag/v1.21.1), sha256
`668506eb17a2eaa1fce6cc0d1f42ef85125d4ac5bda5fc74d1152d0c77145031`).

```sh
pwsh scripts/test.ps1          # extract the Rego to build/rego; opa fmt; canonical layout; opa check --strict; opa test
pwsh scripts/test.ps1 -Fix     # format first: opa fmt over the Rego in the policy files and over tests/
pwsh scripts/preview.ps1       # write PREVIEW.md from fixtures/

# Octopus's OCL parser over every .ocl file (CI runs it; needs the .NET 10 SDK):
git clone https://github.com/OctopusDeploy/Ocl.git build/ocl
git -C build/ocl checkout b01967bd1fb7adb86da740873631b1740a5d7d06
dotnet run --project tools/ocl-check -- .

# The operator only: new fixtures (GET requests to Octopus; the key stays in the demo-environment kit), then the preview.
sudo -n -u aiops -H bash -lc 'cd ~/work/platform-hub/octopus-platform-hub && pwsh -NoProfile -File scripts/build-fixtures.ps1 && pwsh -NoProfile -File scripts/preview.ps1'
```

To change a policy, edit the Rego inside its `.ocl` file, run `scripts/test.ps1 -Fix`, `scripts/test.ps1` and
`scripts/preview.ps1`, and commit `PREVIEW.md` with the change. The workflow
[check.yml](.github/workflows/check.yml) runs on every pull request and on main: the policy checks, the preview as the
job summary (PREVIEW.md must be current), Octopus's OCL parser, and the kit's standard secret scan (gitleaks 8.30.1).
Every change comes by pull request.

## How it gets connected

Plan phase 1, then phase 3 for the policies; phase 2 (the spike) comes before any template is used.

1. **Licence (1.1, Jeffrey).** Done: `GET /api/platformhub/versioncontrol` answers 200 since 2026-10-06.
2. **Repository (1.2, operator).** This repository and its check workflow exist. Still to add: a ruleset on `main`
   (pull request and the required checks `policies` and `secret-scan`).
3. **Version Control (1.3).** Done on 2026-10-07 by the operator through the API (`PUT /api/platformhub/versioncontrol`):
   this repository, base path `.octopus`, default branch `main`, protected, credentials Anonymous. No Platform Hub
   GitHub App connection: policies and templates are edited here, never from the Octopus UI (decision 2026-10-07).
   Should that change, a person signed in to GitHub creates the connection (a service account cannot); never a
   personal token.
4. **Policies (3.2, operator).** Done on 2026-10-07: both published as 1.0.0 and activated
   (`POST /api/platformhub/<ref>/policies/<slug>/publish`, then `.../versions/1.0.0/modify-status`), after the four
   deployments above. The first publish was refused ("User-defined functions are not supported"), which
   `scripts/test.ps1` now checks. Not done: the replay in the Evaluations tab against earlier runs (the API has no
   endpoint for it). Next: watch the promotions to prod of the demo systems (3.3); a deployment that complies logs
   "Compliant with policy ..." under "Apply compliance policies".
5. **Templates (phase 4).** After the spike: publish `cmdemo-process-template` 1.0.0 as a pre-release, share it with the canary
   space only, and remove its DRAFT mark here.

## Open questions for the licence day, with the answers of 2026-10-07

1. Does `Steps` list every step of the process, or only the steps that run in the deployment's environment, channel
   and tenant? The fixtures list every step. If Octopus does too, `prod_has_sign_off` cannot tell a sign-off scoped
   away from prod from one that runs there.
   **Answer:** every step of the process, whatever its environment scope (the fourth deployment above). So neither policy can tell a step scoped away from prod; the kit's fleet covers that.
2. What does `IsConditional` cover: the run condition only, or also a scope by environment, channel or tenant? The
   kit's Sign-off and Record restore point are scoped by environment. Neither policy reads the field; the docs' best
   practice `step.IsConditional == false` would flag every kit Sign-off under the broad reading.
   **Answer:** the broad reading: a step with an environment scope has `IsConditional: true`. The policies must go on not reading it.
3. What `Source` holds for a built-in step. The docs' examples compare `Source.SlugOrId` with a step slug; the
   policies match built-in steps by `Slug` and `ActionType` and do not depend on it.
   **Answer:** `{"Type": "Step", "SlugOrId": "<the step's slug>"}`.
4. `Packages[].Name` (package ID or package reference name) and the format of `GitRef`; `Release.Name`.
5. Which Rego engine and version Octopus runs (the Windows note on a missing Visual C++ runtime suggests a native
   engine). The policies use only common Rego v1: `if`, `in`, `contains`, `else`, comprehensions, `count`, `min`,
   `sprintf`, `concat`, `endswith`.
   **Answer:** not known by name, but it refuses user-defined functions at publish. Values, sets, arrays, comprehensions, `some ... in`, `not`, `count`, `min`, `sprintf` and `concat` are accepted and evaluate as opa does.
6. How the task log and audit log show an allowed result that carries a `reason` (exempt, no database change).
   **Answer:** an allowed result with a reason logs "Compliant with policy \"...\" (<reason>)" at Info level: no warning. A violation in warn mode logs a Warning with the reason, and the task ends Success with warnings.
7. Whether Octopus accepts the Git-authored `cmdemo-process-template.ocl` as it is (name, icon, Teams parameter), and the spike
   items 2 (an exact version as mask) and 5 (its manual intervention answered through `/interruptions`).
