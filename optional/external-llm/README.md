# Optional module: external LLM summary

NOT part of the core deployment. The core product works without it.

Contents: `ExternalLLMService`, `AgentActionExternalLlmSummary`, `ExternalLLMServiceTest` (uses `HttpCalloutMock`).

## Manual setup (cannot be shipped as metadata)
1. Setup > Named Credentials > External Credentials > New: name `SmartSupport_LLM_EC`, protocol Custom, add a Principal and an Authentication Parameter / custom header holding your API key (stored encrypted by Salesforce, never in this repo).
2. Named Credentials > New: **name `SmartSupport_LLM`**, URL = your OpenAI-compatible base URL (for example `https://api.openai.com`), link the External Credential, enable "Generate Authorization Header" or add the header via the External Credential.
3. Give the permission sets that run the action access to the External Credential principal (Permission Set > External Credential Principal Access).
4. Deploy: `sf project deploy start --manifest optional/external-llm/package.xml --target-org <alias>` then run `sf apex run test --tests ExternalLLMServiceTest`.
5. Turn it on: Custom Metadata > Support Setting > Default > `External_LLM_Enabled__c` = true, and set `External_LLM_Model__c`.

The endpoint path is `/v1/chat/completions` (constant in `ExternalLLMService`). Data sent is minimised and PII-scrubbed; output is validated and is a recommendation only. Review your data-processing agreement before enabling it with real customer data.
