import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchKnowledge from '@salesforce/apex/SupportAssistantController.searchKnowledge';
import requestHuman from '@salesforce/apex/SupportAssistantController.requestHuman';
import { reduceError } from 'c/supportUtils';

const MAX_LENGTH = 500;

export default class KnowledgeAssistant extends NavigationMixin(LightningElement) {
    /** Optional. When placed on a Case record page the assistant can hand that case to a human. */
    @api recordId;

    maxLength = MAX_LENGTH;
    question = '';
    result;
    errorMessage;
    humanMessage;
    isLoading = false;
    isRequestingHuman = false;

    get hasCase() {
        return !!this.recordId;
    }

    get isFound() {
        return !!this.result && this.result.status === 'FOUND';
    }

    get articleItems() {
        return (this.result && this.result.articles) || [];
    }

    get isSearchDisabled() {
        return this.isLoading || !this.question || this.question.trim().length === 0;
    }

    get remainingText() {
        return `${MAX_LENGTH - (this.question ? this.question.length : 0)} characters left`;
    }

    handleQuestionChange(event) {
        this.question = event.target.value;
    }

    handleKeyDown(event) {
        // Ctrl/Cmd + Enter submits; plain Enter inserts a new line.
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey) && !this.isSearchDisabled) {
            this.handleSearch();
        }
    }

    async handleSearch() {
        if (this.isSearchDisabled) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        this.humanMessage = undefined;
        this.result = undefined;
        try {
            this.result = await searchKnowledge({
                question: this.question.trim(),
                caseId: this.recordId || null
            });
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleRequestHuman() {
        this.isRequestingHuman = true;
        this.errorMessage = undefined;
        try {
            const response = await requestHuman({ caseId: this.recordId });
            if (response.success) {
                this.humanMessage = response.message;
            } else {
                this.errorMessage = response.message;
            }
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isRequestingHuman = false;
        }
    }

    handleOpenArticle(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Knowledge__kav', actionName: 'view' }
        });
    }
}
