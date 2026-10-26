import { createElement } from 'lwc';
import CaseActionPanel from 'c/caseActionPanel';
import createCase from '@salesforce/apex/SupportAssistantController.createCase';
import getCaseStatus from '@salesforce/apex/SupportAssistantController.getCaseStatus';
import escalateCase from '@salesforce/apex/SupportAssistantController.escalateCase';
import addComment from '@salesforce/apex/SupportAssistantController.addComment';

jest.mock('@salesforce/apex/SupportAssistantController.createCase', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SupportAssistantController.getCaseStatus', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SupportAssistantController.saveSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SupportAssistantController.addComment', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SupportAssistantController.escalateCase', () => ({ default: jest.fn() }), { virtual: true });

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(recordId) {
    const element = createElement('c-case-action-panel', { is: CaseActionPanel });
    if (recordId) {
        element.recordId = recordId;
    }
    document.body.appendChild(element);
    return element;
}

function setInput(element, name, value) {
    // LWC sets "name" as a property on child components (not an HTML attribute), so match on the property.
    const field = Array.from(element.shadowRoot.querySelectorAll('lightning-input, lightning-textarea, lightning-combobox')).find(
        (f) => f.name === name
    );
    field.value = value;
    field.dispatchEvent(new CustomEvent('change'));
}

function button(element, label) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find((b) => b.label === label);
}

describe('c-case-action-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('validates the subject before calling the server', async () => {
        const element = mount();
        button(element, 'Create case').click();
        await flushPromises();
        expect(createCase).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Please enter a subject.');
    });

    it('creates a case and selects it for the other actions', async () => {
        createCase.mockResolvedValue({ success: true, message: 'Case 00001010 was created.', caseId: '500000000000010AAA', caseNumber: '00001010' });
        const element = mount();
        setInput(element, 'subject', 'Invoice question');
        setInput(element, 'description', 'Please explain the charge.');
        await flushPromises();
        button(element, 'Create case').click();
        await flushPromises();

        expect(createCase).toHaveBeenCalledWith({ subject: 'Invoice question', description: 'Please explain the charge.', priority: null });
        const text = element.shadowRoot.textContent;
        expect(text).toContain('Case 00001010 was created.');
        expect(text).toContain('Working on case');
        expect(text).toContain('00001010');
    });

    it('shows the status of a verified case and sends the e-mail only to the server', async () => {
        getCaseStatus.mockResolvedValue({
            found: true,
            caseId: '500000000000011AAA',
            caseNumber: '00001011',
            subject: 'Cannot log in',
            status: 'New',
            priority: 'Medium',
            lastUpdated: '2026-10-24 10:00:00',
            humanHandoffRequired: false,
            message: 'Case 00001011 is currently "New".'
        });
        const element = mount();
        setInput(element, 'caseNumber', '00001011');
        setInput(element, 'contactEmail', 'rao@example.com');
        await flushPromises();
        button(element, 'Get status').click();
        await flushPromises();

        expect(getCaseStatus).toHaveBeenCalledWith({ caseNumber: '00001011', contactEmail: 'rao@example.com' });
        expect(element.shadowRoot.textContent).toContain('Cannot log in');
    });

    it('shows the generic message when the lookup is not verified', async () => {
        getCaseStatus.mockResolvedValue({ found: false, message: 'No matching case was found.' });
        const element = mount();
        setInput(element, 'caseNumber', '99999999');
        await flushPromises();
        button(element, 'Get status').click();
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('No matching case was found.');
        expect(element.shadowRoot.textContent).not.toContain('Last updated');
    });

    it('requires an explicit confirmation before escalating', async () => {
        escalateCase.mockResolvedValue({ success: true, message: 'The case was escalated to a human agent (Manual Escalation).' });
        const element = mount('500000000000012AAA');

        button(element, 'Escalate to a human').click();
        await flushPromises();
        expect(escalateCase).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Do you want to continue?');

        button(element, 'Cancel').click();
        await flushPromises();
        expect(escalateCase).not.toHaveBeenCalled();
        expect(button(element, 'Escalate to a human')).toBeDefined();

        button(element, 'Escalate to a human').click();
        await flushPromises();
        button(element, 'Confirm escalation').click();
        await flushPromises();
        expect(escalateCase).toHaveBeenCalledTimes(1);
        expect(escalateCase).toHaveBeenCalledWith({ caseId: '500000000000012AAA', reason: 'Manual Escalation' });
        expect(element.shadowRoot.textContent).toContain('escalated to a human agent');
    });

    it('disables case actions until a case is selected', () => {
        const element = mount();
        expect(button(element, 'Generate and save summary').disabled).toBe(true);
        expect(button(element, 'Add comment').disabled).toBe(true);
        expect(button(element, 'Escalate to a human').disabled).toBe(true);
    });

    it('adds comments as internal by default', async () => {
        addComment.mockResolvedValue({ success: true, message: 'The comment was added.' });
        const element = mount('500000000000013AAA');
        setInput(element, 'commentBody', 'Called the customer.');
        await flushPromises();
        button(element, 'Add comment').click();
        await flushPromises();
        expect(addComment).toHaveBeenCalledWith({ caseId: '500000000000013AAA', body: 'Called the customer.', isPublic: false });
    });

    it('shows server errors', async () => {
        createCase.mockRejectedValue({ body: { message: 'Insufficient access' } });
        const element = mount();
        setInput(element, 'subject', 'Anything');
        await flushPromises();
        button(element, 'Create case').click();
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('Insufficient access');
    });
});
