package app_deployment_has_health_check_test

import data.app_deployment_has_health_check as policy
import data.policy_input

pin := policy_input.step("pin-id", "pin-version", "Octopus.Script")

update := policy_input.step("update-id", "update-deployable", "Octopus.AzurePowerShell")

verify := policy_input.step("verify-id", "verify-deployable", "Octopus.AzurePowerShell")

tests_step := policy_input.step("tests-id", "acceptance-tests", "Octopus.Script")

apply := policy_input.step("apply-id", "apply-environment", "Octopus.AzurePowerShell")

verify_environment := policy_input.step("verify-environment-id", "verify-environment", "Octopus.AzurePowerShell")

# Scope

test_every_environment_of_a_demo_space_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmdemo1-demo", "tdd", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("cmdemo2-demo", "uat", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("cmdemo3-demo", "prod", [update, verify], [])
}

test_every_environment_of_the_two_named_spaces_of_the_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmfleet", "tdd", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("cmfleet", "prod", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("jeffreypalermo-sites", "uat", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("jeffreypalermo-sites", "prod", [update, verify], [])
}

test_every_environment_of_the_two_spaces_of_the_bible_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("biblefleet", "tdd", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("biblefleet", "uat", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("biblefleet", "prod", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "tdd", [update, verify], [])
	policy.evaluate with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "prod", [update, verify], [])
}

test_the_bootcamp_space_is_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("churchbulletin", "prod", [update], [])
}

test_other_spaces_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("default", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("cmdemo1-demo-archive", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("cmfleet-archive", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("jeffreypalermo", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("biblefleet-archive", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("adam-and-woman", "prod", [update], [])
}

test_runbook_runs_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.runbook_run("cmdemo1-demo", "prod", [update])
	policy.evaluate == false with input as policy_input.runbook_run("cmfleet", "prod", [update])
}

# Allowed

test_a_health_check_after_the_update_complies if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "tdd", [pin, update, verify], [])
}

test_steps_after_the_health_check_do_not_matter if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "tdd", [pin, update, verify, tests_step], [])
}

test_a_deployment_that_updates_no_application_complies if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [apply, verify_environment], [])
	result == {"allowed": true, "reason": "No application is deployed in this deployment."}
}

test_a_skipped_update_is_no_deployment if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [pin, update], ["update-id"])
	result == {"allowed": true, "reason": "No application is deployed in this deployment."}
}

# The processes of the two named spaces, as they were on 2026-10-08.
test_the_processes_of_the_named_spaces_comply if {
	sign_off := policy_input.step("sign-off-id", "sign-off", "Octopus.Manual")
	cmfleet_dashboard := [sign_off, update, verify, policy_input.step("run-tests-id", "run-acceptance-tests", "Octopus.Script")]
	policy.result == {"allowed": true} with input as policy_input.deployment("cmfleet", "prod", cmfleet_dashboard, [])
	jpcom_system := [sign_off, apply, verify_environment]
	system := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "prod", jpcom_system, [])
	system == {"allowed": true, "reason": "No application is deployed in this deployment."}
}

test_no_health_check_in_a_named_space_violates if {
	result := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "tdd", [pin, update], [])
	result.allowed == false
}

# The processes of the two spaces of the Bible fleet, as they were on 2026-10-09.
test_the_processes_of_the_spaces_of_the_bible_fleet_comply if {
	sign_off := policy_input.step("sign-off-id", "sign-off", "Octopus.Manual")
	biblefleet_dashboard := [sign_off, update, verify, policy_input.step("run-tests-id", "run-acceptance-tests", "Octopus.AzurePowerShell")]
	policy.result == {"allowed": true} with input as policy_input.deployment("biblefleet", "prod", biblefleet_dashboard, [])
	adameve_web := [
		sign_off, pin, update, verify,
		policy_input.step("record-id", "record-nodes", "Octopus.Script"),
		policy_input.step("revert-id", "revert-deployable", "Octopus.AzurePowerShell"),
		policy_input.step("verify-revert-id", "verify-revert", "Octopus.AzurePowerShell"),
		policy_input.step("record-after-id", "record-nodes-after-revert", "Octopus.Script"),
		policy_input.step("revert-pin-id", "revert-pin", "Octopus.Script"),
	]
	policy.result == {"allowed": true} with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "tdd", adameve_web, [])
	adameve_system := [sign_off, apply, verify_environment]
	system := policy.result with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "tdd", adameve_system, [])
	system == {"allowed": true, "reason": "No application is deployed in this deployment."}
}

test_no_health_check_in_a_space_of_the_bible_fleet_violates if {
	dashboard := policy.result with input as policy_input.deployment("biblefleet", "uat", [update], [])
	dashboard.allowed == false
	adameve := policy.result with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "tdd", [pin, update], [])
	adameve.allowed == false
}

# Violations

test_no_health_check_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "uat", [pin, update, tests_step], [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step update-deployable deploys the application with no health check after it: add the step verify-deployable after it.",
	}
}

test_a_disabled_health_check_violates if {
	steps := [update, policy_input.disabled(verify)]
	result := policy.result with input as policy_input.deployment("cmdemo2-demo", "prod", steps, [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step update-deployable deploys the application, but its health check does not run: step verify-deployable is disabled.",
	}
}

test_a_skipped_health_check_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo2-demo", "prod", [update, verify], ["verify-id"])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step update-deployable deploys the application, but its health check does not run: step verify-deployable is skipped.",
	}
}

test_a_health_check_before_the_update_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", [verify, update], [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "The health check (verify-deployable) does not run after step update-deployable has finished.",
	}
}

test_a_health_check_that_starts_with_the_update_violates if {
	execution := [
		{"StartTrigger": "StartAfterPrevious", "Steps": ["update-id"]},
		{"StartTrigger": "StartWithPrevious", "Steps": ["verify-id"]},
	]
	deployment := policy_input.with_execution(policy_input.deployment("cmdemo1-demo", "prod", [update, verify], []), execution)
	result := policy.result with input as deployment
	result.allowed == false
	result.reason == "The health check (verify-deployable) does not run after step update-deployable has finished."
}

test_the_health_check_must_follow_the_last_update if {
	second := policy_input.step("update-2-id", "update-deployable", "Octopus.AzurePowerShell")
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [update, verify, second], [])
	result.allowed == false
}
