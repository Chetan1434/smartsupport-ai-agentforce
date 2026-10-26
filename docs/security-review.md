# Security review (self-review, not a formal Salesforce Security Review)

| Area | Implementation |
|---|---|
| Sharing / FLS | Services use `with sharing` and `WITH USER_MODE` / `AccessLevel.USER_MODE`. System mode is used only for the Premium-account lookup (`CustomerContextService.premiumAccountIds`) and the audit logger (`without sharing`, write-only, never throws). |
| Authorization | AI never grants access. A case number alone never authorizes a status lookup: the Agentforce action always requires the contact e-mail; the LWC path requires it for non-Standard (community) users. |
| Injection | Dynamic SOSL is built only from `[a-z0-9]+` tokens. Knowledge snippets with instruction-like markers are excluded. The external LLM prompt wraps case text in delimiters, strips delimiters from input, and validates output against the picklists. |
| Data minimisation / logging | E-mails and 6+ digit runs are masked; text truncated; error messages never include the request text. |
| Human control | Agent comments are internal by default; escalation in the UI needs a confirm step; field updates through `updateApprovedField` are whitelisted (Priority, Status, Issue_Category__c). |
| Secrets | None in the repo. External LLM key lives in a Named/External Credential (manual). |

## Known limitations
- Keyword rules do not understand negation ("no outage") or languages other than English.
- E-mail matching is weak identity verification; use proper authentication for communities in production.
- Custom notifications and queue membership require manual setup.
- Tests have not been executed in an org by the author; see VALIDATION_REPORT.md.
