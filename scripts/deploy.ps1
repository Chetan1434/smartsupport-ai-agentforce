# Deploys the CORE SmartSupport AI package. Usage: .\scripts\deploy.ps1 -Org <alias> [-CheckOnly]
# Runs only THIS project's tests (RunSpecifiedTests) so unrelated tests/triggers in the org do not interfere.
# No credentials are stored here: authenticate first with: sf org login web --alias <alias>
param([Parameter(Mandatory = $true)][string]$Org, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$tests = '--tests AIInteractionLogServiceTest --tests AgentforceActionsTest --tests CaseActionServiceTest --tests CaseIntelligenceServiceTest --tests CaseRoutingRulesTest --tests CaseTriggerHandlerTest --tests CustomerContextServiceTest --tests FlowActionsTest --tests KnowledgeSearchServiceTest --tests QueueRoutingServiceTest --tests SupportControllersTest --tests SupportEscalationServiceTest'.Split(' ')
if ($CheckOnly) {
    sf project deploy validate --manifest manifest/package.xml --target-org $Org --test-level RunSpecifiedTests @tests
} else {
    sf project deploy start --manifest manifest/package.xml --target-org $Org --test-level RunSpecifiedTests @tests
    if ($LASTEXITCODE -eq 0) { sf org assign permset --name SmartSupport_Admin --target-org $Org }
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
