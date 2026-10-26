# Runs this project's Apex tests with coverage. Usage: .\scripts\run-tests.ps1 -Org <alias>
param([Parameter(Mandatory = $true)][string]$Org)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
sf apex run test --target-org $Org --class-names AIInteractionLogServiceTest,AgentforceActionsTest,CaseActionServiceTest,CaseIntelligenceServiceTest,CaseRoutingRulesTest,CaseTriggerHandlerTest,CustomerContextServiceTest,FlowActionsTest,KnowledgeSearchServiceTest,QueueRoutingServiceTest,SupportControllersTest,SupportEscalationServiceTest --code-coverage --result-format human --wait 20 --output-dir test-results
exit $LASTEXITCODE
