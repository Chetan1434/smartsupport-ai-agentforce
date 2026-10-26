# Validation report

Date: 2026-10-25. Environment: Linux container **with no Salesforce org access and no Salesforce CLI authentication**.

## Latest result (reported by the project owner from a real org, 2026-10-26)
`sf project deploy validate --manifest manifest/package.xml --test-level RunSpecifiedTests ...` against a Developer Edition org: **"Successfully validated the deployment", 134 passing, 0 failing, 134 total** (Deploy ID 0AfgK00000XbmM1SAJ). Per-class coverage figures were not captured in that output; run `scripts/run-tests.ps1` and record them here. The sections below describe the earlier offline checks and the fixes that real deploy attempts required. The optional external-LLM module and the Flow/LWC runtime behaviour were not covered by this run. Flows still need manual activation and the manual test plan has not been executed.

## Summary
**(Historical, written before the first org run.) Deployment: not executed by the author. Apex tests: not executed by the author. Code coverage: not measured by the author.** Nothing below should be read as proof that the project deploys or that the Apex tests pass. The checks that *were* run are offline and partial.

## Checks actually executed and their observed results
| Check | Tool | Result |
|---|---|---|
| Apex syntax (parse only, no semantic/type checking) | apex-parser via `node apex-check.mjs` | 37 core files + 3 optional files, **0 syntax errors** |
| XML well-formedness | `xmllint` | 108 XML files, all well-formed |
| Metadata element names against the Metadata API schema bundled with the Salesforce CLI's jsforce (older WSDL) | `scripts/dev/validate_metadata_schema.py` | 104 files checked, 29 reports. All 29 are properties on Flow (`apiVersion`, `environments`, `nameSegment`, `storeOutputAutomatically`, `flowTransactionModel`, `recordTriggerType`, `filterLogic`, `doesRequireRecordChangedToMeetCriteria`, `nextOrFinishButtonLabel`, `isViewedAsPlainText`) and FlexiPage (`itemInstances`) that the bundled schema predates. They are **believed** to be valid in API 65.0 but this is **unverified**: an org deploy is the only authoritative check. No findings on objects, fields, permission sets, queues, app, tabs or custom metadata. |
| Project consistency (`scripts/validate_project.py`): manifest vs files, picklist constants vs field metadata, custom field references in Apex, LWC Apex imports vs `@AuraEnabled` methods, no `SeeAllData`, meta files present | custom script (mutation-tested: injected faults were detected) | **OK** (39 Apex classes, 29 fields) |
| LWC unit tests | `sfdx-lwc-jest` | **5 suites, 23 tests passed** |

## First real deploy attempt (reported by the user, 2026-10-26) and fixes
A deploy validation against a real org returned 51 component errors. Root causes found and fixed:
1. `AIInteractionLogService.sanitize` used a variable named `limit` (reserved in Apex): compile error that cascaded to the Case trigger, Flow actions, controllers, LWCs and permission sets. Renamed. (The offline syntax parser did NOT catch this, so a clean offline parse is weak evidence.)
2. `ExternalLLMService`: enum `Status` clashed (Apex is case-insensitive) with the field `status`. Enum renamed `LlmStatus`.
3. Custom tabs require `<motif>`. Added to both tabs (the earlier offline schema read it as optional).
4. The core manifest used an ApexClass wildcard that also pulled in the optional module. Now an explicit class list; the optional module has its own `optional/external-llm/package.xml`.
5. Second deploy attempt (25 errors): local variables named `number_` are invalid (identifiers cannot end in an underscore). Renamed to `lookupNumber` in `CaseActionService` and two test classes. `scripts/validate_project.py` now lints for reserved-word and trailing-underscore identifiers.
6. Third deploy attempt (user's org, `RunLocalTests`): the code compiled. 172 tests ran in total, 94 passed and 78 failed. Causes:
   - 63 of the failures (the bulk) came from a pre-existing trigger named `case1` in the user's org that throws a NullPointerException on every Case insert. It is not part of this project. The org also contains unrelated triggers/tests (`Covid19PatientTriggerHandlerTest`, `OppTrigger`, ...) that `RunLocalTests` ran and that broke the coverage gate (57% org-wide). The scripts now use `RunSpecifiedTests` with this project's test classes only, and a clean Developer Edition org is recommended.
   - Real defects found and fixed: the dashboard controller did not catch `SecurityException`; tests assumed the deploying admin already had field access (factory now assigns `SmartSupport_Admin` to the test user); one test assumed deployed custom-metadata records are visible during a validation deploy (it now skips when they are not).
7. Fourth deploy attempt (fresh folder, `RunSpecifiedTests`): only this project's 134 tests ran; 103 passed, 31 failed, and 6 classes were below the 75% per-class coverage gate (SupportDashboardController 35.6%, SupportEscalationService 56.8%, CaseIntelligenceService 63.5%, AgentActionClassifyCase 60%, SupportAssistantController 73%, CaseActionService 73.6%). Cause of the failures: the test user had no field-level security on the new custom fields because a permission set assigned mid-test is not applied to the running context. Tests now run inside `System.runAs(SupportTestDataFactory.supportUser())` (a System Administrator-profile user assigned `SmartSupport_Admin`). Coverage numbers should rise once the failing tests run to completion; this is unverified.
These fixes were re-validated in the user's org on the fourth attempt (see the latest result above).

## Defect found after the successful deploy (2026-10-26)
Loading sample data showed cases were classified but not routed to queues. Cause: the manifest used `Queue_Mapping.*` for custom metadata records, which a manifest does not expand, so the 8 `Queue_Mapping__mdt` records were never deployed (the Apex tests did not catch it because they use a test mapping). Fixed by listing each record explicitly; `scripts/validate_project.py` now rejects such wildcards. Re-verification in the org is pending.

## Not executed
- `sf project deploy` (validate or start) - no org.
- All Apex tests: 134 test methods in 12 core test classes plus the optional `ExternalLLMServiceTest` (13 methods). They were written to be meaningful (assertions on outcomes, no `SeeAllData`, in-test data, `HttpCalloutMock`) and the `CaseRoutingRules` tests were walked through by hand against the code, but **none has been run**; failures are possible (for example governor limits, picklist/queue setup, or API behaviour I could not observe).
- Coverage against the 90% goal: unknown.
- Flow activation and runtime behaviour; custom notifications; LWC rendering in a real org; Agentforce actions in an agent.
- Tests that need the "Minimum Access - Salesforce" profile return early when it is absent (they would then pass without testing anything).

## Known risks to check first when you deploy
1. Flow metadata properties listed above (deploy error text will say which).
2. `Queue` + `CustomNotificationType` + Flow ordering in a first deploy (the manifest deploys them together; Salesforce orders dependencies).
3. Apex tests that insert Cases depend on queues/`Queue_Mapping__mdt` (the factory `createQueuesAndMapping` and the shipped metadata) - confirm they pass in a clean org.
4. Optional module needs a Named Credential only at runtime, not at deploy time.

## Reproduce
```
npm install && npm run test:unit
python3 scripts/validate_project.py
sf project deploy validate --manifest manifest/package.xml --target-org <alias> --test-level RunLocalTests
```

## Org verification of routing (reported by the project owner, 2026-10-26)
After deploying the custom metadata records and re-importing `data/cases.csv`, 10 of 11 sample cases were classified and routed as designed (outage -> Urgent_Escalations, security -> Security_Response, billing -> Billing_Support, login -> Account_Access_Support, general -> General_Support). One case ("Scanner arrives with a cracked screen", description "delivered with a cracked screen ... defective") was routed to Shipping because `delivered` was a Shipping keyword. `delivered` was removed from the Shipping keyword list; this change has not been re-validated in the org. Keyword rules remain a known limitation (see docs/security-review.md).
