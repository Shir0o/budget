.PHONY: verify

verify:
	dart format --output=none --set-exit-if-changed .
	flutter analyze
	dart test packages/budget_core
	dart test packages/budget_migration
	dart test packages/budget_simplefin
	dart test packages/budget_mcp
	dart test packages/budget_sync
	dart test packages/budget_store
	(cd app && flutter test)
