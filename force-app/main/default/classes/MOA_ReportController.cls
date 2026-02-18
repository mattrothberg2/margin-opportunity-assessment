/**
 * Controller for MOA_ReportPDF Visualforce page.
 * Loads the latest scan result and formats data for PDF rendering.
 */
public with sharing class MOA_ReportController {

    public MOA_Models.ScanResult result { get; private set; }
    public List<CohortRow> topCohorts { get; private set; }
    public List<RepRow> sortedReps { get; private set; }

    public MOA_ReportController() {
        loadResult();
    }

    private void loadResult() {
        List<MOA_Scan_Result__c> records = [
            SELECT Id, Result_JSON__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        MOA_Scan_Result__c record = records.isEmpty() ? null : records[0];
        if (record != null && String.isNotBlank(record.Result_JSON__c)) {
            result = (MOA_Models.ScanResult) JSON.deserialize(
                record.Result_JSON__c, MOA_Models.ScanResult.class
            );
        } else {
            result = new MOA_Models.ScanResult();
            result.totalDeals = 0;
            result.totalWon = 0;
            result.totalLost = 0;
            result.totalRevenue = 0;
            result.currentAvgMargin = 0;
            result.achievableAvgMargin = 0;
            result.annualOpportunity = 0;
            result.cohorts = new List<MOA_Models.Cohort>();
            result.reps = new List<MOA_Models.RepStats>();
            result.winRateByMarginBand = new List<MOA_Models.MarginBand>();
            result.scanDate = Datetime.now();
            result.scanMonths = 24;
        }
        buildCohortRows();
        buildRepRows();
    }

    // ── Formatted properties ──

    public String scanDateFormatted {
        get {
            if (result.scanDate == null) return 'N/A';
            return result.scanDate.format('MMM d, yyyy h:mm a');
        }
    }

    public String formattedTotalDeals {
        get { return String.valueOf(result.totalDeals); }
    }

    public String formattedTotalRevenue {
        get { return formatCurrency(result.totalRevenue); }
    }

    public String formattedCurrentMargin {
        get { return formatPercent(result.currentAvgMargin); }
    }

    public String formattedAchievableMargin {
        get { return formatPercent(result.achievableAvgMargin); }
    }

    public String formattedAnnualOpportunity {
        get { return formatCurrency(result.annualOpportunity); }
    }

    public String formattedWinRate {
        get {
            if (result.totalDeals == null || result.totalDeals == 0) return '0%';
            Decimal rate = ((Decimal) result.totalWon) / result.totalDeals * 100;
            return rate.setScale(1, RoundingMode.HALF_UP) + '%';
        }
    }

    public Integer cohortCount {
        get { return result.cohorts != null ? result.cohorts.size() : 0; }
    }

    public Integer repCount {
        get { return result.reps != null ? result.reps.size() : 0; }
    }

    // ── Cohort rows ──

    public class CohortRow {
        public String segmentLabel { get; set; }
        public Integer dealCount { get; set; }
        public String winRateFormatted { get; set; }
        public String medianFormatted { get; set; }
        public String avgFormatted { get; set; }
        public String gapFormatted { get; set; }
        public String gapColorClass { get; set; }
        public String oppFormatted { get; set; }
        public String rowClass { get; set; }
        public Decimal sortKey { get; set; }
    }

    private void buildCohortRows() {
        topCohorts = new List<CohortRow>();
        if (result.cohorts == null) return;

        List<CohortRow> allRows = new List<CohortRow>();
        for (Integer i = 0; i < result.cohorts.size(); i++) {
            MOA_Models.Cohort c = result.cohorts[i];
            CohortRow row = new CohortRow();
            row.segmentLabel = c.oem + ' / ' + c.sizeBucket + ' / ' + c.segment;
            row.dealCount = c.dealCount;
            row.winRateFormatted = formatPercent(c.winRate);
            row.medianFormatted = c.medianMargin != null ? formatPercent(c.medianMargin) : '—';
            row.avgFormatted = c.avgMargin != null ? formatPercent(c.avgMargin) : '—';

            Decimal gap = (c.medianMargin != null && c.avgMargin != null)
                ? c.avgMargin - c.medianMargin : 0;
            row.gapFormatted = (gap >= 0 ? '+' : '') + formatPercent(gap);
            row.gapColorClass = gap < 0 ? 'text-red' : 'text-green';
            row.oppFormatted = formatCurrency(c.marginOpportunity);
            row.sortKey = c.marginOpportunity != null ? c.marginOpportunity : 0;
            allRows.add(row);
        }

        // Sort by opportunity descending (bubble sort)
        for (Integer i = 0; i < allRows.size(); i++) {
            for (Integer j = i + 1; j < allRows.size(); j++) {
                if (allRows[j].sortKey > allRows[i].sortKey) {
                    CohortRow temp = allRows[i];
                    allRows[i] = allRows[j];
                    allRows[j] = temp;
                }
            }
        }

        // Take top 10
        for (Integer i = 0; i < Math.min(10, allRows.size()); i++) {
            CohortRow row = allRows[i];
            row.rowClass = Math.mod(i, 2) == 1 ? 'alt' : '';
            topCohorts.add(row);
        }
    }

    // ── Rep rows ──

    public class RepRow {
        public String repName { get; set; }
        public Integer dealCount { get; set; }
        public Integer wonCount { get; set; }
        public String winRateFormatted { get; set; }
        public String avgMarginFormatted { get; set; }
        public String vsTeamFormatted { get; set; }
        public String vsTeamColorClass { get; set; }
        public String consistencyFormatted { get; set; }
        public String oppFormatted { get; set; }
        public String rowClass { get; set; }
        public Decimal sortKey { get; set; }
    }

    private void buildRepRows() {
        sortedReps = new List<RepRow>();
        if (result.reps == null) return;

        List<RepRow> allRows = new List<RepRow>();
        for (MOA_Models.RepStats r : result.reps) {
            RepRow row = new RepRow();
            row.repName = r.repName != null ? r.repName : 'Unknown';
            row.dealCount = r.dealCount != null ? r.dealCount : 0;
            row.wonCount = r.wonCount != null ? r.wonCount : 0;
            Decimal winRate = row.dealCount > 0
                ? ((Decimal) row.wonCount / row.dealCount * 100).setScale(1, RoundingMode.HALF_UP) : 0;
            row.winRateFormatted = formatPercent(winRate);
            row.avgMarginFormatted = formatPercent(r.avgMargin);
            Decimal vsTeam = r.vsTeamAvg != null ? r.vsTeamAvg : 0;
            row.vsTeamFormatted = (vsTeam >= 0 ? '+' : '') + formatPercent(vsTeam);
            row.vsTeamColorClass = vsTeam >= 0 ? 'text-green' : 'text-red';
            row.consistencyFormatted = formatPercent(r.consistency);
            row.oppFormatted = formatCurrency(r.marginLeftOnTable);
            row.sortKey = r.marginLeftOnTable != null ? r.marginLeftOnTable : 0;
            allRows.add(row);
        }

        // Sort by opportunity descending (bubble sort for simplicity)
        for (Integer i = 0; i < allRows.size(); i++) {
            for (Integer j = i + 1; j < allRows.size(); j++) {
                if (allRows[j].sortKey > allRows[i].sortKey) {
                    RepRow temp = allRows[i];
                    allRows[i] = allRows[j];
                    allRows[j] = temp;
                }
            }
        }

        for (Integer i = 0; i < allRows.size(); i++) {
            allRows[i].rowClass = Math.mod(i, 2) == 1 ? 'alt' : '';
            sortedReps.add(allRows[i]);
        }
    }

    // ── Formatters ──

    private static String formatCurrency(Decimal val) {
        if (val == null) return '$0';
        if (val >= 1000000) {
            return '$' + (val / 1000000).setScale(1, RoundingMode.HALF_UP) + 'M';
        }
        if (val >= 1000) {
            return '$' + (val / 1000).setScale(0, RoundingMode.HALF_UP) + 'K';
        }
        return '$' + val.setScale(0, RoundingMode.HALF_UP);
    }

    private static String formatPercent(Decimal val) {
        if (val == null) return '0%';
        return val.setScale(1, RoundingMode.HALF_UP) + '%';
    }
}
