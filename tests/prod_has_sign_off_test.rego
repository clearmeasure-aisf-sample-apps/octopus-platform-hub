package prod_has_sign_off_test

import data.policy_input
import data.prod_has_sign_off as policy

sign_off := policy_input.step("sign-off-id", "sign-off", "Octopus.Manual")

update := policy_input.step("update-id", "update-deployable", "Octopus.AzurePowerShell")

# Scope

test_prod_in_a_demo_space_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, update], [])
}

test_prod_in_the_bootcamp_space_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("churchbulletin", "prod", [update], [])
}

test_prod_in_the_two_named_spaces_of_the_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmfleet", "prod", [sign_off, update], [])
	policy.evaluate with input as policy_input.deployment("jeffreypalermo-sites", "prod", [sign_off, update], [])
}

test_prod_in_the_two_spaces_of_the_bible_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("biblefleet", "prod", [sign_off, update], [])
	policy.evaluate with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "prod", [sign_off, update], [])
}

test_other_environments_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("cmdemo1-demo", "tdd", [update], [])
	policy.evaluate == false with input as policy_input.deployment("cmdemo1-demo", "uat", [update], [])
	policy.evaluate == false with input as policy_input.deployment("churchbulletin", "uat", [update], [])
	policy.evaluate == false with input as policy_input.deployment("cmfleet", "tdd", [update], [])
	policy.evaluate == false with input as policy_input.deployment("jeffreypalermo-sites", "uat", [update], [])
	policy.evaluate == false with input as policy_input.deployment("biblefleet", "uat", [update], [])
	policy.evaluate == false with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "tdd", [update], [])
}

test_other_spaces_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("default", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("devops-bootcamp", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("cmdemo1-demo-archive", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("cmfleet-archive", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("jeffreypalermo", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("biblefleet-archive", "prod", [update], [])
	policy.evaluate == false with input as policy_input.deployment("adam-and-woman", "prod", [update], [])
}

test_runbook_runs_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.runbook_run("cmdemo1-demo", "prod", [update])
}

# Allowed

test_a_manual_intervention_is_a_sign_off if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, update], [])
}

test_a_step_of_the_sign_off_template_is_a_sign_off if {
	templated := policy_input.from_template(policy_input.step("template-id", "sign-off", "Octopus.Script"), "cmdemo-process-template")
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo2-demo", "prod", [templated, update], [])
}

test_one_running_sign_off_is_enough if {
	second := policy_input.step("second-id", "second-sign-off", "Octopus.Manual")
	steps := [sign_off, second, update]
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "prod", steps, ["sign-off-id"])
}

# Violations

test_no_sign_off_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [update], [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "No sign-off in this production deployment: add an enabled manual intervention (Octopus.Manual) or the cmdemo-process-template process template.",
	}
}

test_a_skipped_sign_off_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, update], ["sign-off-id"])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "The sign-off of this production deployment does not run: step sign-off is skipped.",
	}
}

test_a_disabled_sign_off_violates if {
	steps := [policy_input.disabled(sign_off), update]
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", steps, [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "The sign-off of this production deployment does not run: step sign-off is disabled.",
	}
}

test_a_step_of_another_template_is_not_a_sign_off if {
	other := policy_input.from_template(policy_input.step("notify-id", "notify", "Octopus.Script"), "kit-notify")
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [other, update], [])
	result.allowed == false
}

# Exemptions

test_the_exemption_does_not_cover_the_named_spaces if {
	cmfleet := policy.result with input as policy_input.deployment("cmfleet", "prod", [update], [])
	cmfleet.allowed == false
	jpcom := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "prod", [update], [])
	jpcom.allowed == false
}

test_the_exemption_does_not_cover_the_spaces_of_the_bible_fleet if {
	dashboard := policy.result with input as policy_input.deployment("biblefleet", "prod", [update], [])
	dashboard.allowed == false
	adameve := policy.result with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "prod", [update], [])
	adameve.allowed == false
}

test_the_bootcamp_is_exempt if {
	result := policy.result with input as policy_input.deployment("churchbulletin", "prod", [update], [])
	result.allowed == true
	startswith(result.reason, "Exempt: the bootcamp has no Octopus approval by design")
}

test_the_bootcamp_with_a_sign_off_complies if {
	policy.result == {"allowed": true} with input as policy_input.deployment("churchbulletin", "prod", [sign_off, update], [])
}

test_the_exemption_does_not_cover_the_demo_spaces if {
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", [update], [])
	result.allowed == false
}
