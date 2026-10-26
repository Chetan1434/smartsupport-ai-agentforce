#!/usr/bin/env bash
# Deploys the CORE SmartSupport AI package. Usage: scripts/deploy.sh <org-alias> [--check-only]
# Runs only THIS project's tests (RunSpecifiedTests) so unrelated tests/triggers in the org do not interfere.
# No credentials are stored here: authenticate first with: sf org login web --alias <alias>
set -euo pipefail
ORG="${1:?Usage: scripts/deploy.sh <org-alias> [--check-only]}"
MODE="${2:-}"
cd "$(dirname "$0")/.."
TESTS="--tests AIInteractionLogServiceTest --tests AgentforceActionsTest --tests CaseActionServiceTest --tests CaseIntelligenceServiceTest --tests CaseRoutingRulesTest --tests CaseTriggerHandlerTest --tests CustomerContextServiceTest --tests FlowActionsTest --tests KnowledgeSearchServiceTest --tests QueueRoutingServiceTest --tests SupportControllersTest --tests SupportEscalationServiceTest"
if [ "$MODE" = "--check-only" ]; then
  sf project deploy validate --manifest manifest/package.xml --target-org "$ORG" --test-level RunSpecifiedTests $TESTS
else
  sf project deploy start --manifest manifest/package.xml --target-org "$ORG" --test-level RunSpecifiedTests $TESTS
  sf org assign permset --name SmartSupport_Admin --target-org "$ORG" || echo "Permission set assignment skipped (already assigned?)."
fi
