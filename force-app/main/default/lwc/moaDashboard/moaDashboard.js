import { LightningElement, track } from 'lwc';
import startScan from '@salesforce/apex/MOA_ScanController.startScan';
import getScanResult from '@salesforce/apex/MOA_ScanController.getScanResult';
import getScanStatus from '@salesforce/apex/MOA_ScanController.getScanStatus';
import getConfig from '@salesforce/apex/MOA_ScanController.getConfig';

const POLL_INTERVAL = 5000;
const COHORT_DISPLAY_LIMIT = 15;
const TRIAL_DAYS = 30;

export default class MoaDashboard extends LightningElement {
    @track scanResult = null;
    @track isScanning = false;
    @track error = null;
    @track installDate = null;
    @track showAllCohorts = false;
    @track cohortSortField = 'marginOpportunity';
    @track cohortSortAsc = false;
    @track progressProcessed = 0;
    @track progressTotal = 0;

    _pollTimer = null;

    // ── Lifecycle ──

    connectedCallback() {
        this.initialize();
    }

    disconnectedCallback() {
        this.clearPoll();
    }

    async initialize() {
        try {
            const config = await getConfig();
            if (config && config.installDate) {
                this.installDate = config.installDate;
            }
        } catch (e) {
            // Config not available — non-critical
        }

        try {
            const status = await getScanStatus();
            if (status === 'Running') {
                this.isScanning = true;
                this.startPolling();
            } else if (status === 'Complete' || status === 'Error') {
                await this.loadResult();
            }
        } catch (e) {
            // No scan result record yet — show welcome
        }
    }

    async loadResult() {
        try {
            const json = await getScanResult();
            if (json) {
                this.scanResult = JSON.parse(json);
                this.error = null;
            }
        } catch (e) {
            this.error = this.extractError(e);
        }
    }

    // ── Scan Actions ──

    async handleStartScan() {
        this.isScanning = true;
        this.error = null;
        try {
            await startScan();
            this.startPolling();
        } catch (e) {
            this.error = this.extractError(e);
            this.isScanning = false;
        }
    }

    startPolling() {
        this.clearPoll();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => {
            this.pollStatus();
        }, POLL_INTERVAL);
    }

    clearPoll() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async pollStatus() {
        try {
            const status = await getScanStatus();
            if (status === 'Complete') {
                this.clearPoll();
                this.isScanning = false;
                this.progressProcessed = 0;
                this.progressTotal = 0;
                await this.loadResult();
            } else if (status === 'Error') {
                this.clearPoll();
                this.isScanning = false;
                this.progressProcessed = 0;
                this.progressTotal = 0;
                this.error = 'Scan failed. Please try again.';
            } else if (status && status.startsWith('Running: ')) {
                // Parse progress: "Running: 450/2847"
                const parts = status.replace('Running: ', '').split('/');
                if (parts.length === 2) {
                    this.progressProcessed = parseInt(parts[0], 10) || 0;
                    this.progressTotal = parseInt(parts[1], 10) || 0;
                }
            }
        } catch (e) {
            // Keep polling
        }
    }

    // ── Computed: Progress ──

    get hasProgress() {
        return this.progressTotal > 0;
    }

    get progressPercent() {
        if (this.progressTotal <= 0) return 0;
        return Math.min(100, Math.round((this.progressProcessed / this.progressTotal) * 100));
    }

    get progressBarStyle() {
        return 'width: ' + this.progressPercent + '%';
    }

    get progressLabel() {
        return this.progressProcessed + ' / ' + this.progressTotal + ' deals (' + this.progressPercent + '%)';
    }

    // ── Computed: State ──

    get hasResult() {
        return this.scanResult !== null;
    }

    get showWelcome() {
        return !this.hasResult && !this.isScanning && !this.error;
    }

    get scanButtonLabel() {
        if (this.isScanning) return 'Scanning...';
        return this.hasResult ? 'Re-Scan' : 'Scan Now';
    }

    get isScanDisabled() {
        return this.isScanning || this.isTrialExpired;
    }

    get lastScanLabel() {
        if (!this.scanResult || !this.scanResult.scanDate) return null;
        try {
            const d = new Date(this.scanResult.scanDate);
            return d.toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
        } catch (e) {
            return null;
        }
    }

    // ── Computed: Trial ──

    get isTrialExpired() {
        if (!this.installDate) return false;
        const install = new Date(this.installDate);
        const now = new Date();
        const diffDays = Math.floor((now - install) / (1000 * 60 * 60 * 24));
        return diffDays > TRIAL_DAYS;
    }

    // ── Computed: KPIs ──

    get formattedTotalDeals() {
        if (!this.scanResult) return '0';
        return this.formatNumber(this.scanResult.totalDeals);
    }

    get formattedTotalRevenue() {
        if (!this.scanResult) return '$0';
        return this.formatCurrency(this.scanResult.totalRevenue);
    }

    get formattedCurrentMargin() {
        if (!this.scanResult) return '0%';
        return this.formatPercent(this.scanResult.currentAvgMargin);
    }

    get formattedAchievableMargin() {
        if (!this.scanResult) return '0%';
        return this.formatPercent(this.scanResult.achievableAvgMargin);
    }

    get formattedAnnualOpportunity() {
        if (!this.scanResult) return '$0';
        return this.formatCurrency(this.scanResult.annualOpportunity);
    }

    // ── Computed: Cohorts ──

    get sortedCohorts() {
        if (!this.scanResult || !this.scanResult.cohorts) return [];
        const field = this.cohortSortField;
        const asc = this.cohortSortAsc;
        return [...this.scanResult.cohorts]
            .map((c, idx) => this.buildCohortRow(c, idx))
            .sort((a, b) => {
                let va = a.raw[field];
                let vb = b.raw[field];
                if (field === 'segment') {
                    va = a.segmentLabel;
                    vb = b.segmentLabel;
                }
                if (va == null) va = 0;
                if (vb == null) vb = 0;
                if (typeof va === 'string') {
                    return asc ? va.localeCompare(vb) : vb.localeCompare(va);
                }
                return asc ? va - vb : vb - va;
            });
    }

    get displayedCohorts() {
        const all = this.sortedCohorts;
        if (this.showAllCohorts) return all;
        return all.slice(0, COHORT_DISPLAY_LIMIT);
    }

    get hasMoreCohorts() {
        return this.scanResult &&
            this.scanResult.cohorts &&
            this.scanResult.cohorts.length > COHORT_DISPLAY_LIMIT;
    }

    get showAllCohortsLabel() {
        return this.showAllCohorts ? 'Show Top 15' : 'Show All';
    }

    buildCohortRow(c, idx) {
        const gap = (c.medianMargin != null && c.avgMargin != null)
            ? c.avgMargin - c.medianMargin
            : 0;
        const isNegGap = gap < 0;
        return {
            key: c.oem + '|' + c.sizeBucket + '|' + c.segment,
            segmentLabel: c.oem + ' / ' + c.sizeBucket + ' / ' + c.segment,
            dealCount: c.dealCount || 0,
            winRateFormatted: this.formatPercent(c.winRate),
            medianMarginFormatted: c.medianMargin != null ? this.formatPercent(c.medianMargin) : '—',
            avgMarginFormatted: c.avgMargin != null ? this.formatPercent(c.avgMargin) : '—',
            gapFormatted: (isNegGap ? '' : '+') + this.formatPercent(gap),
            gapClass: 'moa-td moa-td-right ' + (isNegGap ? 'moa-text-red' : 'moa-text-green'),
            opportunityFormatted: this.formatCurrency(c.marginOpportunity),
            rowClass: idx % 2 === 0 ? 'moa-row-even' : 'moa-row-odd',
            raw: c
        };
    }

    handleSortCohorts(event) {
        const field = event.currentTarget.dataset.field;
        if (this.cohortSortField === field) {
            this.cohortSortAsc = !this.cohortSortAsc;
        } else {
            this.cohortSortField = field;
            this.cohortSortAsc = field === 'segment';
        }
    }

    handleToggleCohorts() {
        this.showAllCohorts = !this.showAllCohorts;
    }

    // Sort indicators
    get cohortSortIndicator_segment() { return this.getSortIndicator('segment'); }
    get cohortSortIndicator_dealCount() { return this.getSortIndicator('dealCount'); }
    get cohortSortIndicator_winRate() { return this.getSortIndicator('winRate'); }
    get cohortSortIndicator_medianMargin() { return this.getSortIndicator('medianMargin'); }
    get cohortSortIndicator_avgMargin() { return this.getSortIndicator('avgMargin'); }
    get cohortSortIndicator_marginOpportunity() { return this.getSortIndicator('marginOpportunity'); }

    getSortIndicator(field) {
        if (this.cohortSortField !== field) return '';
        return this.cohortSortAsc ? '\u25B2' : '\u25BC';
    }

    // ── Computed: Reps ──

    get hasReps() {
        return this.scanResult && this.scanResult.reps && this.scanResult.reps.length > 0;
    }

    get sortedReps() {
        if (!this.hasReps) return [];
        return [...this.scanResult.reps]
            .map((r, idx) => {
                const winRate = r.dealCount > 0 ? (r.wonCount / r.dealCount * 100) : 0;
                const isPositive = (r.vsTeamAvg || 0) >= 0;
                return {
                    repId: r.repId,
                    repName: r.repName || 'Unknown',
                    dealCount: r.dealCount || 0,
                    wonCount: r.wonCount || 0,
                    winRateFormatted: this.formatPercent(winRate),
                    avgMarginFormatted: this.formatPercent(r.avgMargin),
                    vsTeamFormatted: (isPositive ? '+' : '') + this.formatPercent(r.vsTeamAvg),
                    vsTeamClass: 'moa-td moa-td-right ' + (isPositive ? 'moa-text-green' : 'moa-text-red'),
                    consistencyFormatted: this.formatPercent(r.consistency),
                    opportunityFormatted: this.formatCurrency(r.marginLeftOnTable),
                    rowClass: idx % 2 === 0 ? 'moa-row-even' : 'moa-row-odd',
                    sortVal: r.marginLeftOnTable || 0
                };
            })
            .sort((a, b) => b.sortVal - a.sortVal);
    }

    // ── Computed: Margin Bands ──

    get hasBands() {
        return this.scanResult &&
            this.scanResult.winRateByMarginBand &&
            this.scanResult.winRateByMarginBand.length > 0;
    }

    get formattedBands() {
        if (!this.hasBands) return [];
        const bands = this.scanResult.winRateByMarginBand;
        const maxRate = Math.max(...bands.map(b => b.winRate || 0), 1);
        const sweet = this.sweetSpotBand;

        return bands.map(b => {
            const pct = maxRate > 0 ? ((b.winRate || 0) / maxRate * 100) : 0;
            const isSweet = sweet && b.band === sweet.band;
            return {
                band: b.band,
                dealCount: b.dealCount || 0,
                winRateFormatted: this.formatPercent(b.winRate),
                barStyle: 'width: ' + Math.max(pct, 2) + '%',
                barClass: 'moa-bar-fill' + (isSweet ? ' moa-bar-sweet' : '')
            };
        });
    }

    get sweetSpotBand() {
        if (!this.hasBands) return null;
        let best = null;
        for (const b of this.scanResult.winRateByMarginBand) {
            if ((b.dealCount || 0) >= 10) {
                if (!best || (b.winRate || 0) > (best.winRate || 0)) {
                    best = b;
                }
            }
        }
        return best;
    }

    get sweetSpotLabel() {
        const b = this.sweetSpotBand;
        if (!b) return null;
        return b.band + ' margin band (' + this.formatPercent(b.winRate) + ' win rate)';
    }

    // ── PDF Export ──

    handleExportPdf() {
        // Open the VF page in a new tab — it renders as PDF
        window.open('/apex/MOA_ReportPDF', '_blank');
    }

    // ── CSV Export ──

    handleExportCsv() {
        if (!this.scanResult || !this.scanResult.cohorts) return;

        const rows = [
            ['Segment', 'OEM', 'Size Bucket', 'Customer Segment', 'Deals', 'Won', 'Lost',
             'Win Rate %', 'Median Margin %', 'P25 Margin %', 'P75 Margin %',
             'Avg Margin %', 'Total Revenue', 'Margin Opportunity'].join(',')
        ];

        for (const c of this.scanResult.cohorts) {
            rows.push([
                '"' + (c.oem || '') + ' / ' + (c.sizeBucket || '') + ' / ' + (c.segment || '') + '"',
                '"' + (c.oem || '') + '"',
                '"' + (c.sizeBucket || '') + '"',
                '"' + (c.segment || '') + '"',
                c.dealCount || 0,
                c.wonCount || 0,
                c.lostCount || 0,
                c.winRate || 0,
                c.medianMargin != null ? c.medianMargin : '',
                c.p25Margin != null ? c.p25Margin : '',
                c.p75Margin != null ? c.p75Margin : '',
                c.avgMargin != null ? c.avgMargin : '',
                c.totalRevenue || 0,
                c.marginOpportunity || 0
            ].join(','));
        }

        const csv = rows.join('\n');
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'moa-segment-breakdown.csv';
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    // ── Formatters ──

    formatCurrency(val) {
        if (val == null) return '$0';
        const num = Number(val);
        if (num >= 1000000) {
            return '$' + (num / 1000000).toFixed(1) + 'M';
        }
        if (num >= 1000) {
            return '$' + (num / 1000).toFixed(0) + 'K';
        }
        return '$' + num.toFixed(0);
    }

    formatPercent(val) {
        if (val == null) return '0%';
        return Number(val).toFixed(1) + '%';
    }

    formatNumber(val) {
        if (val == null) return '0';
        return Number(val).toLocaleString();
    }

    extractError(e) {
        if (e && e.body && e.body.message) return e.body.message;
        if (e && e.message) return e.message;
        return 'An unexpected error occurred.';
    }
}
