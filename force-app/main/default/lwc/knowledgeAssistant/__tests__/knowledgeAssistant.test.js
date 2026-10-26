import { createElement } from 'lwc';
import KnowledgeAssistant from 'c/knowledgeAssistant';
import searchKnowledge from '@salesforce/apex/SupportAssistantController.searchKnowledge';
import requestHuman from '@salesforce/apex/SupportAssistantController.requestHuman';

jest.mock('@salesforce/apex/SupportAssistantController.searchKnowledge', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SupportAssistantController.requestHuman', () => ({ default: jest.fn() }), { virtual: true });

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(recordId) {
    const element = createElement('c-knowledge-assistant', { is: KnowledgeAssistant });
    if (recordId) {
        element.recordId = recordId;
    }
    document.body.appendChild(element);
    return element;
}

async function ask(element, text) {
    const textarea = element.shadowRoot.querySelector('lightning-textarea');
    textarea.value = text;
    textarea.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
    element.shadowRoot.querySelector('lightning-button').click();
    await flushPromises();
}

describe('c-knowledge-assistant', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('disables the search button until a question is typed', async () => {
        const element = mount();
        const button = element.shadowRoot.querySelector('lightning-button');
        expect(button.disabled).toBe(true);
        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'How do I reset my password?';
        textarea.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-button').disabled).toBe(false);
    });

    it('shows a grounded answer with its sources', async () => {
        searchKnowledge.mockResolvedValue({
            status: 'FOUND',
            answer: 'According to the Knowledge article "Reset": Use the Forgot password link.',
            humanRecommended: false,
            articles: [{ id: 'ka1', title: 'Reset your password', matchedTerms: 2 }]
        });
        const element = mount();
        await ask(element, 'How do I reset my password?');

        expect(searchKnowledge).toHaveBeenCalledWith({ question: 'How do I reset my password?', caseId: null });
        const text = element.shadowRoot.textContent;
        expect(text).toContain('Forgot password link');
        expect(text).toContain('Reset your password');
        expect(text).not.toContain('Request human support');
    });

    it('shows an explicit no-answer result and offers human support on a case record', async () => {
        searchKnowledge.mockResolvedValue({
            status: 'INSUFFICIENT_EVIDENCE',
            message: 'I could not find a reliable answer in the approved Knowledge articles.',
            humanRecommended: true,
            articles: []
        });
        requestHuman.mockResolvedValue({ success: true, message: 'The case was escalated to a human agent.' });
        const element = mount('500000000000001AAA');
        await ask(element, 'refund policy for enterprise');

        expect(element.shadowRoot.textContent).toContain('could not find a reliable answer');
        expect(searchKnowledge).toHaveBeenCalledWith({ question: 'refund policy for enterprise', caseId: '500000000000001AAA' });

        const humanButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            (b) => b.label === 'Request human support'
        );
        expect(humanButton).toBeDefined();
        humanButton.click();
        await flushPromises();
        expect(requestHuman).toHaveBeenCalledWith({ caseId: '500000000000001AAA' });
        expect(element.shadowRoot.textContent).toContain('escalated to a human agent');
    });

    it('explains how to get human support when not on a case record', async () => {
        searchKnowledge.mockResolvedValue({ status: 'UNAVAILABLE', message: 'Knowledge is not enabled.', humanRecommended: true, articles: [] });
        const element = mount();
        await ask(element, 'anything at all');
        expect(element.shadowRoot.textContent).toContain('Create a case in the Case Actions panel');
    });

    it('shows an error when the server call fails', async () => {
        searchKnowledge.mockRejectedValue({ body: { message: 'Server unavailable' } });
        const element = mount();
        await ask(element, 'How do I reset my password?');
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Server unavailable');
    });
});
