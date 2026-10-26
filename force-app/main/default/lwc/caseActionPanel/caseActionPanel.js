import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createCase from '@salesforce/apex/SupportAssistantController.createCase';
import getCaseStatus from '@salesforce/apex/SupportAssistantController.getCaseStatus';
import saveSummary from '@salesforce/apex/SupportAssistantController.saveSummary';
import addComment from '@salesforce/apex/SupportAssistantController.addComment';
import escalateCase from '@salesforce/apex/SupportAssistantController.escalateCase';
import { reduceError } from 'c/supportUtils';

const PRIORITY_OPTIONS = [
    { label: 'High', value: 'High' },
    { label: 'Medium', value: 'Medium' },
    { label: 'Low', value: 'Low' }
];

// Must match SupportConstants.VALID_REASONS in Apex. The server validates the value again.
const REASON_OPTIONS = [
    { label: 'Manual Escalation', value: 'Manual Escalation' },
    { label: 'Security Concern', value: 'Security Concern' },
    { label: 'Widespread Outage', value: 'Widespread Outage' },
    { label: 'Customer Requested Human', value: 'Customer Requested Human' },
    { label: 'Insufficient Knowledge', value: 'Insufficient Knowledge' }
];

export default class CaseActionPanel extends LightningElement {
    /** Set automatically when the component is placed on a Case record page. */
    @api recordId;

    priorityOptions = PRIORITY_OPTIONS;
    reasonOptions = REASON_OPTIONS;

    // form state
    subject = '';
    description = '';
    priority;
    caseNumber = '';
    contactEmail = '';
    commentBody = '';
    commentPublic = false;
    reason = 'Manual Escalation';

    // results
    selectedCaseId;
    selectedCaseNumber;
    statusResult;
    summaryResult;
    feedback;
    isBusy = false;
    awaitingConfirmation = false;

    get activeCaseId() {
        return this.recordId || this.selectedCaseId;
    }

    get hasActiveCase() {
        return !!this.activeCaseId;
    }

    get activeCaseLabel() {
        return this.selectedCaseNumber || (this.recordId ? 'this record' : '');
    }

    get isActionDisabled() {
        return this.isBusy || !this.hasActiveCase;
    }

    get feedbackClass() {
        const base = 'slds-var-m-bottom_small slds-box slds-box_x-small ';
        return base + (this.feedback && this.feedback.success ? 'slds-theme_success' : 'slds-theme_error');
    }

    get humanAttentionText() {
        if (!this.statusResult) {
            return '';
        }
        return this.statusResult.humanHandoffRequired ? 'Yes - a human agent is needed' : 'No';
    }

    handleFieldChange(event) {
        const { name, value } = event.target;
        this[name] = value;
    }

    handleCheckboxChange(event) {
        this[event.target.name] = event.target.checked;
    }

    showFeedback(success, message) {
        this.feedback = { success, message };
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /** Runs a server call with a busy indicator and uniform error handling. */
    async run(action) {
        this.isBusy = true;
        this.feedback = undefined;
        try {
            await action();
        } catch (error) {
            this.showFeedback(false, reduceError(error));
        } finally {
            this.isBusy = false;
        }
    }

    handleCreate() {
        if (!this.subject || this.subject.trim().length === 0) {
            this.showFeedback(false, 'Please enter a subject.');
            return;
        }
        return this.run(async () => {
            const result = await createCase({
                subject: this.subject.trim(),
                description: this.description,
                priority: this.priority || null
            });
            this.showFeedback(result.success, result.message);
            if (result.success) {
                this.selectedCaseId = result.caseId;
                this.selectedCaseNumber = result.caseNumber;
                this.subject = '';
                this.description = '';
                this.priority = undefined;
                this.toast('Case created', result.message, 'success');
            }
        });
    }

    handleStatus() {
        if (!this.caseNumber || this.caseNumber.trim().length === 0) {
            this.showFeedback(false, 'Please enter a case number.');
            return;
        }
        return this.run(async () => {
            const result = await getCaseStatus({
                caseNumber: this.caseNumber.trim(),
                contactEmail: this.contactEmail || null
            });
            this.statusResult = result.found ? result : undefined;
            this.showFeedback(result.found, result.message);
            if (result.found) {
                this.selectedCaseId = result.caseId;
                this.selectedCaseNumber = result.caseNumber;
            }
        });
    }

    handleSummarize() {
        return this.run(async () => {
            const insight = await saveSummary({ caseId: this.activeCaseId });
            this.summaryResult = insight;
            this.showFeedback(true, 'The summary was saved on the case.');
        });
    }

    handleComment() {
        if (!this.commentBody || this.commentBody.trim().length === 0) {
            this.showFeedback(false, 'Please enter a comment.');
            return;
        }
        return this.run(async () => {
            const result = await addComment({
                caseId: this.activeCaseId,
                body: this.commentBody,
                isPublic: this.commentPublic
            });
            this.showFeedback(result.success, result.message);
            if (result.success) {
                this.commentBody = '';
                this.commentPublic = false;
            }
        });
    }

    handleEscalateClick() {
        this.awaitingConfirmation = true;
    }

    handleEscalateCancel() {
        this.awaitingConfirmation = false;
    }

    handleEscalateConfirm() {
        return this.run(async () => {
            const result = await escalateCase({ caseId: this.activeCaseId, reason: this.reason });
            this.showFeedback(result.success, result.message);
            this.awaitingConfirmation = false;
            if (result.success) {
                this.toast('Case escalated', result.message, 'success');
            }
        });
    }
}
