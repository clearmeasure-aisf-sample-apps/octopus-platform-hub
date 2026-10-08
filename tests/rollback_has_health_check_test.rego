package rollback_has_health_check_test

import data.policy_input
import data.rollback_has_health_check as policy

sign_off := policy_input.step("sign-off-id", "sign-off", "Octopus.Manual")

pin := policy_input.step("pin-id", "pin-version", "Octopus.Script")

update := policy_input.step("update-id", "update-deployable", "Octopus.AzurePowerShell")

# The update step of runtime aks-argocd: Argo CD deploys what the pin says.
argo_update := policy_input.step("update-id", "update-deployable", "Octopus.ArgoCDUpdateImageTags")

verify := policy_input.step("verify-id", "verify-deployable", "Octopus.AzurePowerShell")

record := policy_input.step("record-id", "record-nodes", "Octopus.Script")

revert := policy_input.step("revert-id", "revert-deployable", "Octopus.AzurePowerShell")

verify_revert := policy_input.step("verify-revert-id", "verify-revert", "Octopus.AzurePowerShell")

record_after := policy_input.step("record-after-id", "record-nodes-after-revert", "Octopus.Script")

revert_pin := policy_input.step("revert-pin-id", "revert-pin", "Octopus.Script")

# The processes of the fleet on 2026-10-08. Each step after record-nodes runs on failure, which the input does not say.
jpcom_web := [sign_off, pin, update, verify, record, revert, verify_revert, record_after, revert_pin]

jpcom_dashboard := [sign_off, pin, update, verify, revert_pin]

cmfleet_dashboard := [sign_off, update, verify, policy_input.step("run-tests-id", "run-acceptance-tests", "Octopus.Script")]

# A cluster project of runtime aks-argocd since the kit's commit 8ebb204 (cmdemo3), and the process its releases
# made before that carry.
aks := [sign_off, pin, argo_update, verify, revert_pin, verify_revert]

aks_before := [sign_off, pin, argo_update, verify, revert_pin]

# Scope

test_every_environment_of_a_demo_space_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmdemo1-demo", "tdd", jpcom_web, [])
	policy.evaluate with input as policy_input.deployment("cmdemo2-demo", "uat", jpcom_web, [])
	policy.evaluate with input as policy_input.deployment("cmdemo3-demo", "prod", aks, [])
}

test_every_environment_of_the_two_named_spaces_of_the_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmfleet", "tdd", cmfleet_dashboard, [])
	policy.evaluate with input as policy_input.deployment("cmfleet", "prod", cmfleet_dashboard, [])
	policy.evaluate with input as policy_input.deployment("jeffreypalermo-sites", "uat", jpcom_web, [])
	policy.evaluate with input as policy_input.deployment("jeffreypalermo-sites", "prod", jpcom_web, [])
}

test_the_bootcamp_space_is_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("churchbulletin", "prod", [update, revert], [])
}

test_other_spaces_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("default", "prod", [update, revert], [])
	policy.evaluate == false with input as policy_input.deployment("cmdemo1-demo-archive", "prod", [update, revert], [])
	policy.evaluate == false with input as policy_input.deployment("cmfleet-archive", "prod", [update, revert], [])
	policy.evaluate == false with input as policy_input.deployment("jeffreypalermo", "prod", [update, revert], [])
}

test_runbook_runs_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.runbook_run("cmdemo1-demo", "prod", [update, revert])
	policy.evaluate == false with input as policy_input.runbook_run("jeffreypalermo-sites", "prod", [update, revert])
}

# Allowed

test_a_health_check_after_the_rollback_complies if {
	policy.result == {"allowed": true} with input as policy_input.deployment("jeffreypalermo-sites", "prod", jpcom_web, [])
}

test_a_health_check_after_the_reverted_pin_complies_where_argo_cd_deploys if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo3-demo", "prod", aks, [])
}

test_any_argo_cd_update_makes_the_reverted_pin_a_rollback if {
	manifests := policy_input.step("update-id", "update-deployable", "Octopus.ArgoCDUpdateManifests")
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo3-demo", "uat", [manifests, revert_pin, verify_revert], [])
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "uat", [manifests, revert_pin], [])
	result.allowed == false
}

test_a_reverted_pin_is_no_rollback_where_argo_cd_does_not_deploy if {
	result := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "prod", jpcom_dashboard, [])
	result == {"allowed": true, "reason": "No rollback step runs in this deployment."}
}

test_a_process_without_a_rollback_step_complies if {
	dashboard := policy.result with input as policy_input.deployment("cmfleet", "prod", cmfleet_dashboard, [])
	dashboard == {"allowed": true, "reason": "No rollback step runs in this deployment."}
	apply := policy_input.step("apply-id", "apply-environment", "Octopus.AzurePowerShell")
	verify_environment := policy_input.step("verify-environment-id", "verify-environment", "Octopus.AzurePowerShell")
	system := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "prod", [sign_off, apply, verify_environment], [])
	system == {"allowed": true, "reason": "No rollback step runs in this deployment."}
}

test_a_skipped_or_disabled_rollback_is_no_rollback if {
	skipped := policy.result with input as policy_input.deployment("cmdemo1-demo", "tdd", [update, verify, revert], ["revert-id"])
	skipped == {"allowed": true, "reason": "No rollback step runs in this deployment."}
	disabled := policy.result with input as policy_input.deployment("cmdemo1-demo", "tdd", [update, verify, policy_input.disabled(revert)], [])
	disabled == {"allowed": true, "reason": "No rollback step runs in this deployment."}
}

test_any_step_whose_slug_starts_with_verify_is_a_health_check if {
	other := policy_input.step("verify-rollback-id", "verify-rollback", "Octopus.Script")
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "prod", [update, verify, revert, other], [])
}

test_a_step_in_parallel_between_them_keeps_the_order if {
	deployment := policy_input.deployment("cmdemo1-demo", "prod", [update, revert, record_after, verify_revert], [])
	execution := [
		{"StartTrigger": "StartAfterPrevious", "Steps": ["update-id"]},
		{"StartTrigger": "StartAfterPrevious", "Steps": ["revert-id"]},
		{"StartTrigger": "StartWithPrevious", "Steps": ["record-after-id"]},
		{"StartTrigger": "StartAfterPrevious", "Steps": ["verify-revert-id"]},
	]
	policy.result == {"allowed": true} with input as policy_input.with_execution(deployment, execution)
}

# The default runtime's last step only makes Git say again what runs: the health check need not follow it.
test_the_reverted_pin_after_the_health_check_does_not_matter_where_argo_cd_does_not_deploy if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "prod", [update, verify, revert, verify_revert, revert_pin], [])
}

# Violations

test_a_reverted_pin_with_nothing_after_it_violates_where_argo_cd_deploys if {
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", aks_before, [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step revert-pin puts the earlier version back in service with no health check after it: add a step after it whose slug starts with verify- (the kit's verify-revert).",
	}
}

test_the_health_check_of_the_update_is_not_the_one_of_the_rollback if {
	result := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "tdd", [pin, update, verify, record, revert], [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step revert-deployable puts the earlier version back in service with no health check after it: add a step after it whose slug starts with verify- (the kit's verify-revert).",
	}
}

test_a_health_check_before_the_rollback_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [update, verify_revert, revert], [])
	result.allowed == false
}

test_a_skipped_health_check_violates if {
	result := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "prod", jpcom_web, ["verify-revert-id"])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step revert-deployable puts the earlier version back in service, but the health check after it does not run: step verify-revert is skipped.",
	}
}

test_a_disabled_health_check_violates if {
	steps := [sign_off, pin, argo_update, verify, revert_pin, policy_input.disabled(verify_revert)]
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", steps, [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step revert-pin puts the earlier version back in service, but the health check after it does not run: step verify-revert is disabled.",
	}
}

test_a_health_check_that_starts_with_the_rollback_violates if {
	execution := [
		{"StartTrigger": "StartAfterPrevious", "Steps": ["update-id"]},
		{"StartTrigger": "StartAfterPrevious", "Steps": ["revert-id"]},
		{"StartTrigger": "StartWithPrevious", "Steps": ["verify-revert-id"]},
	]
	deployment := policy_input.with_execution(policy_input.deployment("cmdemo1-demo", "prod", [update, revert, verify_revert], []), execution)
	result := policy.result with input as deployment
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "The health check (verify-revert) starts before step revert-deployable has finished.",
	}
}

# Where Argo CD deploys, both steps put a version back: the health check follows the last of them.
test_the_health_check_must_follow_the_last_rollback if {
	steps := [argo_update, verify, revert, verify_revert, revert_pin]
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", steps, [])
	result.allowed == false
	result.reason == "Step revert-pin puts the earlier version back in service with no health check after it: add a step after it whose slug starts with verify- (the kit's verify-revert)."
}

# No exemption

# cmdemo3 was exempt in version 1.0.0, until both of its cluster projects had deployed to prod a release with the step
# verify-revert. A release it made before that violates like any other.
test_cmdemo3_with_a_process_without_the_health_check_violates if {
	prod := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", aks_before, [])
	prod == {
		"allowed": false,
		"action": "warn",
		"reason": "Step revert-pin puts the earlier version back in service with no health check after it: add a step after it whose slug starts with verify- (the kit's verify-revert).",
	}
	tdd := policy.result with input as policy_input.deployment("cmdemo3-demo", "tdd", aks_before, [])
	tdd == prod
}
