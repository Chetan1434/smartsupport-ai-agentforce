import { createElement } from 'lwc';
import CaseIntelligencePanel from 'c/caseIntelligencePanel';
import { getRecord } from 'lightning/uiRecordApi';
import getInsight from '@salesforce/apex/SupportAssistantController.getInsight';
import saveSummary from '@salesforce/apex/SupportAssistantController.saveSummary';

jest.mock('@salesforce/apex/SupportAssistantController.getInsight', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SupportAssistantController.saveSummary', () => ({ default: jest.fn() }), { virtual: true });

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

const INSIGHT = {
    caseId: '500000000000020AAA',
    summary: 'Technical issue, negative sentiment: Service is down.',
    issueCategory: 'Technical',
    sentiment: 'Negative',
    priority: 'High',
    recommendedPriority: 'High',
    recommendedQueue: 'Urgent_Escalations',
    recommendedAction: 'Check open incidents and notify the on-call team.',
    escalationRecommended: true,
    escalationReason: 'Widespread Outage',
    explanation: 'Category "Technical" from outage: service is down.',
    failedAttempts: 0,
    troubleshootingSteps: ['Capture exact error messages.', 'Escalate to engineering.']
};

const CASE_RECORD = { fields: { Subject: { value: 'Service is down' }, Description: { value: 'All users affected' } } };

function mount() {
    const element = createElement('c-case-intelligence-panel', { is: CaseIntelligencePanel });
    element.recordId = '500000000000020AAA';
    document.body.appendChild(element);
    return element;
}

describe('c-case-intelligence-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads and shows the insight when the case record arrives', async () => {
        getInsight.mockResolvedValue(INSIGHT);
        const element = mount();
        getRecord.emit(CASE_RECORD);
        await flushPromises();

        expect(getInsight).toHaveBeenCalledWith({ caseId: '500000000000020AAA' });
        const text = element.shadowRoot.textContent;
        expect(text).toContain('Service is down');
        expect(text).toContain('Technical');
        expect(text).toContain('Urgent_Escalations');
        expect(text).toContain('Human handoff required: Widespread Outage');
        expect(text).toContain('Capture exact error messages.');
        expect(text).toContain('recommendation only');
    });

    it('does not reload when the case text did not change', async () => {
        getInsight.mockResolvedValue(INSIGHT);
        mount();
        getRecord.emit(CASE_RECORD);
        await flushPromises();
        getRecord.emit(CASE_RECORD);
        await flushPromises();
        expect(getInsight).toHaveBeenCalledTimes(1);
    });

    it('shows an error when the analysis fails', async () => {
        getInsight.mockRejectedValue({ body: { message: 'Case not found or you do not have access to it.' } });
        const element = mount();
        getRecord.emit(CASE_RECORD);
        await flushPromises();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('not found or you do not have access');
    });

    it('saves the summary on demand', async () => {
        getInsight.mockResolvedValue(INSIGHT);
        saveSummary.mockResolvedValue({ ...INSIGHT, summary: 'Saved summary text' });
        const element = mount();
        getRecord.emit(CASE_RECORD);
        await flushPromises();

        const save = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find((b) => b.label === 'Save summary to case');
        save.click();
        await flushPromises();
        expect(saveSummary).toHaveBeenCalledWith({ caseId: '500000000000020AAA' });
        expect(element.shadowRoot.textContent).toContain('Saved summary text');
    });
});
