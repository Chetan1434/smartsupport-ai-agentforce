import { reduceError, priorityBadgeClass, sentimentBadgeClass, sentimentIcon } from 'c/supportUtils';

describe('c-support-utils', () => {
    it('reduceError handles every error shape', () => {
        expect(reduceError(undefined)).toBe('An unknown error occurred.');
        expect(reduceError({ body: { message: 'Apex failed' } })).toBe('Apex failed');
        expect(reduceError({ body: [{ message: 'A' }, { message: 'B' }] })).toBe('A, B');
        expect(reduceError({ message: 'JS error' })).toBe('JS error');
        expect(reduceError('plain text')).toBe('plain text');
        expect(reduceError({ unexpected: true })).toBe('An unexpected error occurred.');
    });

    it('maps priority and sentiment to badge classes', () => {
        expect(priorityBadgeClass('High')).toContain('slds-theme_error');
        expect(priorityBadgeClass('Medium')).toContain('slds-theme_warning');
        expect(priorityBadgeClass('Low')).toBe('slds-badge');
        expect(sentimentBadgeClass('Negative')).toContain('slds-theme_error');
        expect(sentimentBadgeClass('Positive')).toContain('slds-theme_success');
        expect(sentimentBadgeClass('Neutral')).toBe('slds-badge');
    });

    it('maps sentiment to an icon', () => {
        expect(sentimentIcon('Negative')).toBe('utility:warning');
        expect(sentimentIcon('Positive')).toBe('utility:like');
        expect(sentimentIcon(undefined)).toBe('utility:info');
    });
});
