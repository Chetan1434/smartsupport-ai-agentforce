#!/usr/bin/env bash
# Runs this project's Apex tests with coverage. Usage: scripts/run-tests.sh <org-alias>
set -euo pipefail
ORG="${1:?Usage: scripts/run-tests.sh <org-alias>}"
cd "$(dirname "$0")/.."
sf apex run test --target-org "$ORG" --class-names AIInteractionLogServiceTest,AgentforceActionsTest,CaseActionServiceTest,CaseIntelligenceServiceTest,CaseRoutingRulesTest,CaseTriggerHandlerTest,CustomerContextServiceTest,FlowActionsTest,KnowledgeSearchServiceTest,QueueRoutingServiceTest,SupportControllersTest,SupportEscalationServiceTest --code-coverage --result-format human --wait 20 --output-dir test-results
