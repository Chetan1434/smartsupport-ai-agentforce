import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getRecordNotifyChange } from 'lightning/uiRecordApi';
import CASE_SUBJECT from '@salesforce/schema/Case.Subject';
import CASE_DESCRIPTION from '@salesforce/schema/Case.Description';
import getInsight from '@salesforce/apex/SupportAssistantController.getInsight';
import saveSummary from '@salesforce/apex/SupportAssistantController.saveSummary';
import { reduceError, priorityBadgeClass, sentimentBadgeClass, sentimentIcon } from 'c/supportUtils';

export default class CaseIntelligencePanel extends LightningElement {
    @api recordId;

    insight;
    errorMessage;
    isBusy = false;
    lastSignature;

    /**
     * Lightning Data Service: re-analyse whenever the case text changes (for example after an agent edits it).
     * The analysis itself runs on the server with the user's permissions.
     */
    @wire(getRecord, { recordId: '$recordId', fields: [CASE_SUBJECT, CASE_DESCRIPTION] })
    wiredCase({ data, error }) {
        if (data) {
            const signature = `${data.fields.Subject.value}|${data.fields.Description.value}`;
            if (signature !== this.lastSignature) {
                this.lastSignature = signature;
                this.loadInsight();
            }
        } else if (error) {
            this.errorMessage = reduceError(error);
        }
    }

    get hasSteps() {
        return !!(this.insight && this.insight.troubleshootingSteps && this.insight.troubleshootingSteps.length);
    }

    get stepItems() {
        const steps = (this.insight && this.insight.troubleshootingSteps) || [];
        return steps.map((text, index) => ({ key: `step-${index}`, text }));
    }

    get escalationReasonLabel() {
        return (this.insight && this.insight.escalationReason) || 'Escalation recommended';
    }

    get sentimentClass() {
        return sentimentBadgeClass(this.insight && this.insight.sentiment);
    }

    get sentimentIconName() {
        return sentimentIcon(this.insight && this.insight.sentiment);
    }

    get recommendedPriorityClass() {
        return priorityBadgeClass(this.insight && this.insight.recommendedPriority);
    }

    async loadInsight() {
        if (!this.recordId) {
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            this.insight = await getInsight({ caseId: this.recordId });
        } catch (error) {
            this.insight = undefined;
            this.errorMessage = reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handleRefresh() {
        this.loadInsight();
    }

    async handleSave() {
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            this.insight = await saveSummary({ caseId: this.recordId });
            await getRecordNotifyChange([{ recordId: this.recordId }]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Summary saved',
                    message: 'The summary and recommendations were saved on the case.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = reduceError(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save the summary',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }
}
