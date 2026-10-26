import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getDashboardData from '@salesforce/apex/SupportDashboardController.getDashboardData';
import { reduceError, priorityBadgeClass, sentimentBadgeClass } from 'c/supportUtils';

export default class SmartSupportDashboard extends NavigationMixin(LightningElement) {
    data;
    errorMessage;
    isLoading = true;
    wiredResult;

    @wire(getDashboardData)
    wiredDashboard(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.data = data;
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.data = undefined;
            this.errorMessage = reduceError(error);
            this.isLoading = false;
        }
    }

    get hasData() {
        return !!this.data;
    }

    get metrics() {
        const d = this.data || {};
        return [
            { key: 'open', label: 'Open cases', value: d.openCases, cssClass: 'metric' },
            {
                key: 'high',
                label: 'High priority',
                value: d.highPriorityCases,
                cssClass: d.highPriorityCases > 0 ? 'metric metric-alert' : 'metric'
            },
            {
                key: 'human',
                label: 'Awaiting human',
                value: d.humanAttentionCases,
                cssClass: d.humanAttentionCases > 0 ? 'metric metric-warn' : 'metric'
            },
            {
                key: 'negative',
                label: 'Negative sentiment',
                value: d.negativeSentimentCases,
                cssClass: d.negativeSentimentCases > 0 ? 'metric metric-warn' : 'metric'
            },
            { key: 'escalated', label: 'Escalated', value: d.escalatedCases, cssClass: 'metric' }
        ];
    }

    get attentionRows() {
        return ((this.data && this.data.attentionCases) || []).map((c) => ({
            ...c,
            sentimentLabel: c.sentiment || 'Unknown',
            priorityClass: priorityBadgeClass(c.priority),
            sentimentClass: sentimentBadgeClass(c.sentiment),
            recommendedAction: c.recommendedAction || 'No recommendation yet'
        }));
    }

    get hasAttentionCases() {
        return this.attentionRows.length > 0;
    }

    get categoryRows() {
        const rows = (this.data && this.data.openByCategory) || [];
        const max = rows.reduce((m, r) => Math.max(m, r.total), 0) || 1;
        return rows.map((r) => ({
            ...r,
            barStyle: `width: ${Math.round((r.total / max) * 100)}%`
        }));
    }

    get hasCategories() {
        return this.categoryRows.length > 0;
    }

    get interactionRows() {
        return ((this.data && this.data.recentInteractions) || []).map((log) => ({
            ...log,
            when: log.createdDate ? new Date(log.createdDate).toLocaleString() : ''
        }));
    }

    get hasInteractions() {
        return this.interactionRows.length > 0;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredResult).finally(() => {
            this.isLoading = false;
        });
    }

    handleOpenCase(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Case', actionName: 'view' }
        });
    }
}
