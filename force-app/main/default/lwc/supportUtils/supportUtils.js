/**
 * Small shared helpers for the SmartSupport components (no Apex, no secrets, no DOM access).
 */

/** Turns any error shape (Apex, LDS, JS) into one readable sentence. */
export function reduceError(error) {
    if (!error) {
        return 'An unknown error occurred.';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    if (typeof error.message === 'string') {
        return error.message;
    }
    if (typeof error === 'string') {
        return error;
    }
    return 'An unexpected error occurred.';
}

/** SLDS badge classes for a Case priority. */
export function priorityBadgeClass(priority) {
    if (priority === 'High') {
        return 'slds-badge slds-theme_error';
    }
    if (priority === 'Medium') {
        return 'slds-badge slds-theme_warning';
    }
    return 'slds-badge';
}

/** SLDS badge classes for a sentiment value. */
export function sentimentBadgeClass(sentiment) {
    if (sentiment === 'Negative') {
        return 'slds-badge slds-theme_error';
    }
    if (sentiment === 'Positive') {
        return 'slds-badge slds-theme_success';
    }
    return 'slds-badge';
}

/** Small icon name for a sentiment value (decorative; text is always shown next to it). */
export function sentimentIcon(sentiment) {
    if (sentiment === 'Negative') {
        return 'utility:warning';
    }
    if (sentiment === 'Positive') {
        return 'utility:like';
    }
    return 'utility:info';
}
