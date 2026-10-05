package policy_input

# Builders of policy inputs for the tests, in the shape of the documented input schema
# (https://octopus.com/docs/platform-hub/policies/schema, copied to schema/policy-input.schema.json).

# A built-in step: enabled, not required, default conditions. Its Source is empty, as in the fixtures (the
# documentation does not say what Source holds for a step that comes from neither kind of template).
step(id, slug, action_type) := {
	"Id": id,
	"Slug": slug,
	"ActionType": action_type,
	"Enabled": true,
	"IsRequired": false,
	"IsConditional": false,
	"Source": {"Type": "", "SlugOrId": ""},
}

disabled(s) := object.union(s, {"Enabled": false})

# A step that a process template contributes.
from_template(s, template) := object.union(s, {"Source": {"Type": "Process Template", "SlugOrId": template, "Version": "1.0.0"}})

# A deployment to an environment of a space, every step in its own execution group, one after the other.
deployment(space, environment, steps, skipped) := {
	"Environment": {"Id": "Environments-1", "Name": environment, "Slug": environment, "Tags": []},
	"Project": {"Id": "Projects-1", "Name": "app", "Slug": "app", "Tags": []},
	"Space": {"Id": "Spaces-1", "Name": space, "Slug": space},
	"ProjectGroup": {"Id": "ProjectGroups-1", "Name": "app", "Slug": "app"},
	"Steps": steps,
	"SkippedSteps": skipped,
	"Execution": [{"StartTrigger": "StartAfterPrevious", "Steps": [s.Id]} | some s in steps],
	"RequiresApproval": false,
	"Actor": {"Id": "Users-1", "Username": "ai-ops", "Type": "Agent"},
	"CreatedAt": "2026-10-05T00:00:00.000Z",
	"Release": {"Id": "Releases-1", "Name": "1.0.0", "Version": "1.0.0"},
}

# The same deployment with its own execution groups.
with_execution(d, execution) := object.union(d, {"Execution": execution})

# A runbook run: Runbook instead of Release.
runbook_run(space, environment, steps) := object.union(
	object.remove(deployment(space, environment, steps, []), ["Release"]),
	{"Runbook": {"Id": "Runbooks-1", "Name": "Restore test", "Snapshot": "Snapshot 1"}},
)
