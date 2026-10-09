package prod_db_change_has_restore_point_test

import data.policy_input
import data.prod_db_change_has_restore_point as policy

sign_off := policy_input.step("sign-off-id", "sign-off", "Octopus.Manual")

restore_point := policy_input.step("restore-point-id", "record-restore-point", "Octopus.AzurePowerShell")

pin := policy_input.step("pin-id", "pin-version", "Octopus.Script")

migrate := policy_input.step("migrate-id", "migrate-database", "Octopus.AzurePowerShell")

update := policy_input.step("update-id", "update-deployable", "Octopus.AzurePowerShell")

# The bootcamp's DbUp step: a version-controlled process, whose step IDs are the slugs.
dbup := policy_input.step("run-db-migrations", "run-db-migrations", "Octopus.Script")

# The order of the kit's deployable projects.
kit := [sign_off, restore_point, pin, migrate, update]

# Scope

test_prod_in_a_demo_space_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmdemo1-demo", "prod", kit, [])
}

test_prod_in_the_bootcamp_space_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("churchbulletin", "prod", [dbup, update], [])
}

test_prod_in_the_two_named_spaces_of_the_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("cmfleet", "prod", [sign_off, update], [])
	policy.evaluate with input as policy_input.deployment("jeffreypalermo-sites", "prod", [sign_off, pin, update], [])
}

test_prod_in_the_two_spaces_of_the_bible_fleet_is_in_scope if {
	policy.evaluate with input as policy_input.deployment("biblefleet", "prod", [sign_off, update], [])
	policy.evaluate with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "prod", [sign_off, pin, update], [])
}

test_other_environments_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("cmdemo1-demo", "tdd", kit, [])
	policy.evaluate == false with input as policy_input.deployment("churchbulletin", "tdd", [dbup, update], [])
	policy.evaluate == false with input as policy_input.deployment("cmfleet", "uat", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("jeffreypalermo-sites", "tdd", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("biblefleet", "uat", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "tdd", [migrate], [])
}

test_other_spaces_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.deployment("default", "prod", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("training", "prod", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("cmfleet-archive", "prod", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("jeffreypalermo", "prod", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("biblefleet-archive", "prod", [migrate], [])
	policy.evaluate == false with input as policy_input.deployment("adam-and-woman", "prod", [migrate], [])
}

test_runbook_runs_are_out_of_scope if {
	policy.evaluate == false with input as policy_input.runbook_run("cmdemo1-demo", "prod", [migrate])
}

# Allowed

test_no_database_change_is_allowed if {
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, pin, update], [])
	result == {"allowed": true, "reason": "No database change runs in this deployment."}
}

test_a_skipped_or_disabled_migration_is_no_change if {
	skipped := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, migrate], ["migrate-id"])
	skipped.allowed == true
	disabled := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, policy_input.disabled(migrate)], [])
	disabled.allowed == true
}

test_the_kit_order_complies if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo1-demo", "prod", kit, [])
}

test_the_templates_comply if {
	templated_restore_point := policy_input.from_template(policy_input.step("t1", "back-up", "Octopus.Script"), "kit-record-restore-point")
	templated_migration := policy_input.from_template(policy_input.step("t2", "apply-migrations", "Octopus.Script"), "kit-migrate-database")
	steps := [sign_off, templated_restore_point, templated_migration, update]
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo2-demo", "prod", steps, [])
}

test_a_step_in_parallel_between_them_keeps_the_order if {
	deployment := policy_input.deployment("cmdemo1-demo", "prod", [restore_point, pin, migrate], [])
	execution := [
		{"StartTrigger": "StartAfterPrevious", "Steps": ["restore-point-id"]},
		{"StartTrigger": "StartWithPrevious", "Steps": ["pin-id"]},
		{"StartTrigger": "StartAfterPrevious", "Steps": ["migrate-id"]},
	]
	policy.result == {"allowed": true} with input as policy_input.with_execution(deployment, execution)
}

test_a_named_space_without_a_database_change_is_allowed if {
	result := policy.result with input as policy_input.deployment("jeffreypalermo-sites", "prod", [sign_off, pin, update], [])
	result == {"allowed": true, "reason": "No database change runs in this deployment."}
}

test_the_spaces_of_the_bible_fleet_without_a_database_change_are_allowed if {
	dashboard := policy.result with input as policy_input.deployment("biblefleet", "prod", [sign_off, update], [])
	dashboard == {"allowed": true, "reason": "No database change runs in this deployment."}
	adameve := policy.result with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "prod", [sign_off, pin, update], [])
	adameve == {"allowed": true, "reason": "No database change runs in this deployment."}
}

test_a_database_change_with_no_restore_point_in_a_space_of_the_bible_fleet_violates if {
	result := policy.result with input as policy_input.deployment("adam-and-woman-in-the-garden-of-eden", "prod", [sign_off, migrate, update], [])
	result.allowed == false
}

# Violations

test_a_migration_without_restore_point_violates if {
	result := policy.result with input as policy_input.deployment("churchbulletin", "prod", [dbup, update], [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step run-db-migrations changes the database with no restore point before it: add the step record-restore-point or the process template kit-record-restore-point before the first database change.",
	}
}

test_a_restore_point_after_the_migration_violates if {
	steps := [sign_off, migrate, restore_point, update]
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", steps, [])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step migrate-database changes the database before the restore point (record-restore-point) has finished.",
	}
}

test_a_restore_point_in_parallel_with_the_migration_violates if {
	deployment := policy_input.deployment("cmdemo1-demo", "prod", [restore_point, migrate], [])
	execution := [
		{"StartTrigger": "StartAfterPrevious", "Steps": ["restore-point-id"]},
		{"StartTrigger": "StartWithPrevious", "Steps": ["migrate-id"]},
	]
	result := policy.result with input as policy_input.with_execution(deployment, execution)
	result.allowed == false
	result.reason == "Step migrate-database changes the database before the restore point (record-restore-point) has finished."
}

test_a_skipped_restore_point_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo2-demo", "prod", kit, ["restore-point-id"])
	result == {
		"allowed": false,
		"action": "warn",
		"reason": "Step migrate-database changes the database, but its restore point does not run: step record-restore-point is skipped.",
	}
}

test_a_disabled_restore_point_violates if {
	steps := [sign_off, policy_input.disabled(restore_point), pin, migrate, update]
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", steps, [])
	result.allowed == false
	result.reason == "Step migrate-database changes the database, but its restore point does not run: step record-restore-point is disabled."
}

test_a_migration_without_restore_point_in_a_named_space_violates if {
	result := policy.result with input as policy_input.deployment("cmfleet", "prod", [sign_off, migrate, update], [])
	result.allowed == false
}

# Exemptions

test_cmdemo3_without_a_restore_point_violates if {
	result := policy.result with input as policy_input.deployment("cmdemo3-demo", "prod", [sign_off, migrate, update], [])
	result.allowed == false
}

test_a_data_step_is_not_a_database_change if {
	middle_names := policy_input.step("middle-names-id", "set-employee-middle-names", "Octopus.AzurePowerShell")
	initialize := policy_input.step("initialize-id", "initialize-database", "Octopus.Script")
	result := policy.result with input as policy_input.deployment("cmdemo1-demo", "prod", [sign_off, middle_names, initialize, update], [])
	result == {"allowed": true, "reason": "No database change runs in this deployment."}
}

test_cmdemo3_with_a_restore_point_complies if {
	policy.result == {"allowed": true} with input as policy_input.deployment("cmdemo3-demo", "prod", kit, [])
}

test_the_exemption_does_not_cover_the_bootcamp if {
	result := policy.result with input as policy_input.deployment("churchbulletin", "prod", [dbup], [])
	result.allowed == false
}
