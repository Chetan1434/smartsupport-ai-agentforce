import { createElement } from 'lwc';
import SmartSupportDashboard from 'c/smartSupportDashboard';
import getDashboardData from '@salesforce/apex/SupportDashboardController.getDashboardData';

jest.mock(
    '@salesforce/apex/SupportDashboardController.getDashboardData',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const DATA = {
    openCases: 12,
    highPriorityCases: 3,
    humanAttentionCases: 2,
    negativeSentimentCases: 4,
    escalatedCases: 1,
    attentionCases: [
        {
            id: '500000000000001AAA',
            caseNumber: '00001001',
            subject: 'Service is down',
            priority: 'High',
            status: 'New',
            sentiment: 'Negative',
            issueCategory: 'Technical',
            humanHandoffRequired: true,
            recommendedAction: 'Check open incidents',
            ownerName: 'Urgent Escalations'
        }
    ],
    openByCategory: [
        { label: 'Technical', total: 6 },
        { label: 'Billing', total: 3 }
    ],
    recentInteractions: [
        {
            id: 'a00000000000001AAA',
            name: 'AIL-0001',
            caseNumber: '00001001',
            interactionType: 'Escalation',
            outcome: 'Escalated',
            source: 'Rules',
            createdDate: '2026-10-24T10:00:00.000Z'
        }
    ]
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
    const element = createElement('c-smart-support-dashboard', { is: SmartSupportDashboard });
    document.body.appendChild(element);
    return element;
}

describe('c-smart-support-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the metrics, attention cases, categories and AI history', async () => {
        const element = mount();
        getDashboardData.emit(DATA);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('Open cases');
        expect(text).toContain('12');
        expect(text).toContain('Awaiting human');
        expect(text).toContain('00001001');
        expect(text).toContain('Check open incidents');
        expect(text).toContain('Technical');
        expect(text).toContain('Escalation');
        expect(element.shadowRoot.querySelectorAll('.metric').length).toBe(5);
        expect(element.shadowRoot.querySelectorAll('.metric-alert').length).toBe(1);
    });

    it('shows friendly empty states', async () => {
        const element = mount();
        getDashboardData.emit({ ...DATA, attentionCases: [], openByCategory: [], recentInteractions: [] });
        await flushPromises();
        const text = element.shadowRoot.textContent;
        expect(text).toContain('No high-priority cases');
        expect(text).toContain('No open cases.');
        expect(text).toContain('No AI interactions recorded yet.');
    });

    it('shows the server error message', async () => {
        const element = mount();
        // the Apex wire test adapter wraps the given object as error.body
        getDashboardData.error({ message: 'No permission' });
        await flushPromises();
        const alert = element.shadowRoot.querySelector('[role="alert"]');
        expect(alert).not.toBeNull();
        expect(alert.textContent).toContain('No permission');
    });
});
