/**
 * Core analysis engine for Margin Opportunity Assessment.
 * Database.Batchable that scans Closed Won/Lost Opportunities and
 * computes margin opportunity statistics by cohort.
 * No external calls — everything runs in Apex.
 */
public with sharing class MOA_Scanner implements Database.Batchable<SObject>, Database.Stateful {

    // ── Inner data classes (not serialized to result — intermediate only) ──

    public class DealData {
        public Id oppId;
        public String oppName;
        public Decimal amount;
        public Boolean isWon;
        public String oem;
        public String sizeBucket;
        public String segment;
        public Decimal marginPercent; // null if unknown
        public Id ownerId;
        public String ownerName;
        public String cohortKey;
    }

    public class RepAccumulator {
        public String repName;
        public Id repId;
        public Integer dealCount = 0;
        public Integer wonCount = 0;
        public Decimal marginSum = 0;
        public Integer marginDealCount = 0;
        public List<Decimal> marginValues = new List<Decimal>();
        public List<Decimal> vsMedianValues = new List<Decimal>();
        public Decimal marginLeftOnTable = 0;
    }

    // ── Known OEM patterns ──

    private static final List<String> OEM_NAMES = new List<String>{
        'Cisco', 'Dell', 'HPE', 'Lenovo', 'Microsoft', 'Palo Alto',
        'CrowdStrike', 'Fortinet', 'VMware', 'NetApp', 'Juniper', 'Aruba'
    };

    // ── Margin field names to try (in order) ──

    private static final List<String> MARGIN_FIELDS = new List<String>{
        'Fulcrum_GP_Percent__c',
        'GP_Percent__c',
        'Margin_Percent__c'
    };

    // ── Stateful accumulation ──

    private Map<String, List<DealData>> cohortDeals = new Map<String, List<DealData>>();
    private Map<Id, RepAccumulator> repMap = new Map<Id, RepAccumulator>();
    private List<DealData> allDeals = new List<DealData>();
    private Integer scanMonths;
    private Integer minCohortSize;
    private Integer processedCount = 0;
    private Integer totalCount = 0;

    public MOA_Scanner(Integer scanMonths, Integer minCohortSize) {
        this.scanMonths = scanMonths != null ? scanMonths : 24;
        this.minCohortSize = minCohortSize != null ? minCohortSize : 5;
    }

    // ── Batchable interface ──

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Get total count for progress reporting
        String countQuery = 'SELECT COUNT() FROM Opportunity '
            + 'WHERE IsClosed = true '
            + 'AND CloseDate >= LAST_N_MONTHS:' + this.scanMonths + ' '
            + 'AND Amount > 0';
        this.totalCount = Database.countQuery(countQuery);

        String query = 'SELECT Id, Name, Amount, StageName, CloseDate, Type, OwnerId, IsClosed, IsWon, '
            + 'Account.Industry, Account.AnnualRevenue, Account.NumberOfEmployees, Account.Name, '
            + 'Owner.Name, '
            + '(SELECT ProductCode, UnitPrice, Quantity, TotalPrice, Product2.Family, Product2.Name '
            + ' FROM OpportunityLineItems) '
            + 'FROM Opportunity '
            + 'WHERE IsClosed = true '
            + 'AND CloseDate >= LAST_N_MONTHS:' + this.scanMonths + ' '
            + 'AND Amount > 0';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (SObject sobj : scope) {
            Opportunity opp = (Opportunity) sobj;
            DealData deal = extractDeal(opp);
            allDeals.add(deal);

            // Add to cohort map
            if (!cohortDeals.containsKey(deal.cohortKey)) {
                cohortDeals.put(deal.cohortKey, new List<DealData>());
            }
            cohortDeals.get(deal.cohortKey).add(deal);

            // Accumulate rep stats
            if (!repMap.containsKey(deal.ownerId)) {
                RepAccumulator ra = new RepAccumulator();
                ra.repId = deal.ownerId;
                ra.repName = deal.ownerName;
                repMap.put(deal.ownerId, ra);
            }
            RepAccumulator rep = repMap.get(deal.ownerId);
            rep.dealCount++;
            if (deal.isWon) {
                rep.wonCount++;
            }
            if (deal.marginPercent != null) {
                rep.marginSum += deal.marginPercent;
                rep.marginDealCount++;
                rep.marginValues.add(deal.marginPercent);
            }
        }

        // Update progress
        this.processedCount += scope.size();
        try {
            List<MOA_Scan_Result__c> records = [
                SELECT Id, Scan_Status__c FROM MOA_Scan_Result__c ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!records.isEmpty()) {
                records[0].Scan_Status__c = 'Running: ' + this.processedCount + '/' + this.totalCount;
                update records[0];
            }
        } catch (Exception e) {
            // Progress update is non-critical — don't fail the batch
        }
    }

    public void finish(Database.BatchableContext bc) {
        try {
            MOA_Models.ScanResult result = computeResult();
            String resultJson = JSON.serialize(result);

            MOA_Scan_Result__c record = getOrCreateResultRecord();
            record.Result_JSON__c = resultJson;
            record.Scan_Status__c = 'Complete';
            record.Error_Message__c = null;
            record.Scan_Date__c = Datetime.now();
            upsert record;

            MOA_Config__c config = MOA_Config__c.getOrgDefaults();
            if (config.Id != null) {
                config.Last_Scan_Date__c = Datetime.now();
                update config;
            }
        } catch (Exception e) {
            MOA_Scan_Result__c record = getOrCreateResultRecord();
            record.Scan_Status__c = 'Error';
            record.Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString();
            record.Scan_Date__c = Datetime.now();
            upsert record;
        }
    }

    private static MOA_Scan_Result__c getOrCreateResultRecord() {
        List<MOA_Scan_Result__c> records = [
            SELECT Id, Result_JSON__c, Scan_Status__c, Error_Message__c, Scan_Date__c
            FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!records.isEmpty()) {
            return records[0];
        }
        return new MOA_Scan_Result__c();
    }

    // ── Deal extraction ──

    @TestVisible
    private DealData extractDeal(Opportunity opp) {
        DealData deal = new DealData();
        deal.oppId = opp.Id;
        deal.oppName = opp.Name;
        deal.amount = opp.Amount;
        deal.isWon = opp.IsWon;
        deal.ownerId = opp.OwnerId;
        deal.ownerName = opp.Owner != null ? opp.Owner.Name : 'Unknown';

        // Derive OEM
        deal.oem = deriveOem(opp);

        // Derive Size Bucket
        deal.sizeBucket = deriveSizeBucket(opp.Amount);

        // Derive Customer Segment
        Decimal annualRevenue = opp.Account != null ? opp.Account.AnnualRevenue : null;
        deal.segment = deriveSegment(annualRevenue);

        // Derive Margin
        deal.marginPercent = deriveMargin(opp);

        // Build cohort key
        deal.cohortKey = deal.oem + '|' + deal.sizeBucket + '|' + deal.segment;

        return deal;
    }

    @TestVisible
    private static String deriveOem(Opportunity opp) {
        List<OpportunityLineItem> lineItems = opp.OpportunityLineItems;
        if (lineItems == null || lineItems.isEmpty()) {
            return 'Other';
        }

        // Use the highest-value line item
        OpportunityLineItem primary = lineItems[0];
        for (OpportunityLineItem li : lineItems) {
            if (li.TotalPrice != null && (primary.TotalPrice == null || li.TotalPrice > primary.TotalPrice)) {
                primary = li;
            }
        }

        // Check Product2.Family first, then Product2.Name, then ProductCode
        String familyText = '';
        if (primary.Product2 != null) {
            if (String.isNotBlank(primary.Product2.Family)) {
                familyText += primary.Product2.Family + ' ';
            }
            if (String.isNotBlank(primary.Product2.Name)) {
                familyText += primary.Product2.Name + ' ';
            }
        }
        if (String.isNotBlank(primary.ProductCode)) {
            familyText += primary.ProductCode;
        }
        familyText = familyText.toUpperCase();

        for (String oem : OEM_NAMES) {
            if (familyText.contains(oem.toUpperCase())) {
                return oem;
            }
        }
        return 'Other';
    }

    @TestVisible
    private static String deriveSizeBucket(Decimal amount) {
        if (amount == null) return 'Unknown';
        if (amount >= 1000000) return '$1M+';
        if (amount >= 500000) return '$500K-1M';
        if (amount >= 100000) return '$100K-500K';
        if (amount >= 25000) return '$25K-100K';
        return '<$25K';
    }

    @TestVisible
    private static String deriveSegment(Decimal annualRevenue) {
        if (annualRevenue == null) return 'Unknown';
        if (annualRevenue >= 1000000000) return 'Enterprise';
        if (annualRevenue >= 100000000) return 'Mid-Market';
        if (annualRevenue >= 10000000) return 'SMB';
        return 'Unknown';
    }

    @TestVisible
    private static Decimal deriveMargin(Opportunity opp) {
        // Try known custom margin fields
        for (String fieldName : MARGIN_FIELDS) {
            try {
                Object val = opp.get(fieldName);
                if (val != null) {
                    return (Decimal) val;
                }
            } catch (Exception e) {
                // Field doesn't exist in this org — continue
            }
        }

        // Fallback: try to compute from line item cost data
        List<OpportunityLineItem> lineItems = opp.OpportunityLineItems;
        if (lineItems != null && !lineItems.isEmpty()) {
            Decimal totalRevenue = 0;
            Decimal totalCost = 0;
            Boolean hasCost = false;

            for (OpportunityLineItem li : lineItems) {
                if (li.TotalPrice != null) {
                    totalRevenue += li.TotalPrice;
                }
                try {
                    Object costVal = li.get('Cost__c');
                    if (costVal != null) {
                        totalCost += (Decimal) costVal;
                        hasCost = true;
                    }
                } catch (Exception e) {
                    // No Cost__c field
                }
                if (!hasCost) {
                    try {
                        Object costVal = li.get('UnitCost__c');
                        if (costVal != null) {
                            totalCost += (Decimal) costVal * (li.Quantity != null ? li.Quantity : 1);
                            hasCost = true;
                        }
                    } catch (Exception e) {
                        // No UnitCost__c field
                    }
                }
            }

            if (hasCost && totalRevenue > 0) {
                return ((totalRevenue - totalCost) / totalRevenue * 100).setScale(2, RoundingMode.HALF_UP);
            }
        }

        // No margin data available
        return null;
    }

    // ── Result computation (called from finish) ──

    @TestVisible
    private MOA_Models.ScanResult computeResult() {
        MOA_Models.ScanResult result = new MOA_Models.ScanResult();
        result.scanDate = Datetime.now();
        result.scanMonths = this.scanMonths;

        // Totals
        Integer totalDeals = 0;
        Integer totalWon = 0;
        Integer totalLost = 0;
        Decimal totalRevenue = 0;
        Decimal marginWeightedSum = 0;
        Decimal marginWeightedAmount = 0;

        for (DealData d : allDeals) {
            totalDeals++;
            if (d.isWon) {
                totalWon++;
                totalRevenue += d.amount != null ? d.amount : 0;
            } else {
                totalLost++;
            }
            if (d.isWon && d.marginPercent != null && d.amount != null) {
                marginWeightedSum += d.marginPercent * d.amount;
                marginWeightedAmount += d.amount;
            }
        }

        result.totalDeals = totalDeals;
        result.totalWon = totalWon;
        result.totalLost = totalLost;
        result.totalRevenue = totalRevenue.setScale(2, RoundingMode.HALF_UP);
        result.currentAvgMargin = marginWeightedAmount > 0
            ? (marginWeightedSum / marginWeightedAmount).setScale(2, RoundingMode.HALF_UP)
            : 0;

        // ── Cohort analysis ──

        List<MOA_Models.Cohort> cohorts = new List<MOA_Models.Cohort>();
        Map<String, Decimal> cohortMedians = new Map<String, Decimal>();
        Decimal achievableWeightedSum = 0;
        Decimal achievableWeightedAmount = 0;
        Decimal totalOpportunity = 0;

        for (String key : cohortDeals.keySet()) {
            List<DealData> deals = cohortDeals.get(key);
            if (deals.size() < this.minCohortSize) continue;

            String[] parts = key.split('\\|');
            MOA_Models.Cohort cohort = new MOA_Models.Cohort();
            cohort.oem = parts[0];
            cohort.sizeBucket = parts[1];
            cohort.segment = parts[2];

            Integer cDealCount = 0;
            Integer cWonCount = 0;
            Integer cLostCount = 0;
            Decimal cTotalRevenue = 0;
            List<Decimal> wonMargins = new List<Decimal>();
            List<Decimal> allMargins = new List<Decimal>();

            for (DealData d : deals) {
                cDealCount++;
                if (d.isWon) {
                    cWonCount++;
                    cTotalRevenue += d.amount != null ? d.amount : 0;
                } else {
                    cLostCount++;
                }
                if (d.marginPercent != null) {
                    allMargins.add(d.marginPercent);
                    if (d.isWon) {
                        wonMargins.add(d.marginPercent);
                    }
                }
            }

            cohort.dealCount = cDealCount;
            cohort.wonCount = cWonCount;
            cohort.lostCount = cLostCount;
            cohort.winRate = cDealCount > 0
                ? (((Decimal) cWonCount) / cDealCount * 100).setScale(1, RoundingMode.HALF_UP)
                : 0;
            cohort.totalRevenue = cTotalRevenue.setScale(2, RoundingMode.HALF_UP);

            if (!allMargins.isEmpty()) {
                allMargins.sort();
                cohort.medianMargin = computeMedian(allMargins);
                cohort.p25Margin = computePercentile(allMargins, 25);
                cohort.p75Margin = computePercentile(allMargins, 75);
                cohort.avgMargin = computeAverage(allMargins);
                cohortMedians.put(key, cohort.medianMargin);

                // Opportunity: sum of gaps for won deals below median
                Decimal cohortOpp = 0;
                for (DealData d : deals) {
                    if (d.isWon && d.marginPercent != null && d.amount != null) {
                        if (d.marginPercent < cohort.medianMargin) {
                            Decimal gap = cohort.medianMargin - d.marginPercent;
                            cohortOpp += (gap / 100) * d.amount;
                        }
                        // For achievable avg margin
                        Decimal effectiveMargin = d.marginPercent < cohort.medianMargin
                            ? cohort.medianMargin : d.marginPercent;
                        achievableWeightedSum += effectiveMargin * d.amount;
                        achievableWeightedAmount += d.amount;
                    }
                }
                cohort.marginOpportunity = cohortOpp.setScale(2, RoundingMode.HALF_UP);
                totalOpportunity += cohortOpp;
            } else {
                cohort.medianMargin = null;
                cohort.p25Margin = null;
                cohort.p75Margin = null;
                cohort.avgMargin = null;
                cohort.marginOpportunity = 0;
            }

            cohorts.add(cohort);
        }

        result.cohorts = cohorts;
        result.achievableAvgMargin = achievableWeightedAmount > 0
            ? (achievableWeightedSum / achievableWeightedAmount).setScale(2, RoundingMode.HALF_UP)
            : 0;
        result.annualOpportunity = this.scanMonths > 0
            ? (totalOpportunity * (12.0 / this.scanMonths)).setScale(2, RoundingMode.HALF_UP)
            : 0;

        // ── Rep analysis ──

        Decimal teamMarginSum = 0;
        Integer teamMarginCount = 0;
        for (RepAccumulator ra : repMap.values()) {
            teamMarginSum += ra.marginSum;
            teamMarginCount += ra.marginDealCount;
        }
        Decimal teamAvgMargin = teamMarginCount > 0 ? teamMarginSum / teamMarginCount : 0;

        // Compute per-rep vs-median values using cohort medians
        for (RepAccumulator ra : repMap.values()) {
            ra.marginLeftOnTable = 0;
            // Reprocess each deal for this rep to compute vs-median
        }
        for (DealData d : allDeals) {
            if (d.marginPercent != null && cohortMedians.containsKey(d.cohortKey)) {
                RepAccumulator ra = repMap.get(d.ownerId);
                if (ra != null) {
                    Decimal median = cohortMedians.get(d.cohortKey);
                    ra.vsMedianValues.add(d.marginPercent - median);
                    if (d.isWon && d.marginPercent < median && d.amount != null) {
                        ra.marginLeftOnTable += ((median - d.marginPercent) / 100) * d.amount;
                    }
                }
            }
        }

        List<MOA_Models.RepStats> reps = new List<MOA_Models.RepStats>();
        for (RepAccumulator ra : repMap.values()) {
            MOA_Models.RepStats rs = new MOA_Models.RepStats();
            rs.repName = ra.repName;
            rs.repId = String.valueOf(ra.repId);
            rs.dealCount = ra.dealCount;
            rs.wonCount = ra.wonCount;
            rs.avgMargin = ra.marginDealCount > 0
                ? (ra.marginSum / ra.marginDealCount).setScale(2, RoundingMode.HALF_UP)
                : 0;
            rs.vsTeamAvg = ra.marginDealCount > 0
                ? (rs.avgMargin - teamAvgMargin).setScale(2, RoundingMode.HALF_UP)
                : 0;
            rs.consistency = !ra.vsMedianValues.isEmpty()
                ? computeStdDev(ra.vsMedianValues)
                : 0;
            rs.marginLeftOnTable = ra.marginLeftOnTable.setScale(2, RoundingMode.HALF_UP);
            reps.add(rs);
        }
        result.reps = reps;

        // ── Win rate by margin band ──

        Map<String, Integer> bandTotal = new Map<String, Integer>();
        Map<String, Integer> bandWon = new Map<String, Integer>();
        List<String> bandLabels = new List<String>{ '0-5%', '5-10%', '10-15%', '15-20%', '20-25%', '25%+' };
        for (String b : bandLabels) {
            bandTotal.put(b, 0);
            bandWon.put(b, 0);
        }

        for (DealData d : allDeals) {
            if (d.marginPercent == null) continue;
            String band = marginToBand(d.marginPercent);
            bandTotal.put(band, bandTotal.get(band) + 1);
            if (d.isWon) {
                bandWon.put(band, bandWon.get(band) + 1);
            }
        }

        List<MOA_Models.MarginBand> bands = new List<MOA_Models.MarginBand>();
        for (String label : bandLabels) {
            MOA_Models.MarginBand mb = new MOA_Models.MarginBand();
            mb.band = label;
            mb.dealCount = bandTotal.get(label);
            mb.winRate = mb.dealCount > 0
                ? (((Decimal) bandWon.get(label)) / mb.dealCount * 100).setScale(1, RoundingMode.HALF_UP)
                : 0;
            bands.add(mb);
        }
        result.winRateByMarginBand = bands;

        return result;
    }

    // ── Math helpers ──

    @TestVisible
    private static Decimal computeMedian(List<Decimal> sortedValues) {
        if (sortedValues.isEmpty()) return 0;
        Integer n = sortedValues.size();
        if (Math.mod(n, 2) == 1) {
            return sortedValues[n / 2].setScale(2, RoundingMode.HALF_UP);
        }
        return ((sortedValues[n / 2 - 1] + sortedValues[n / 2]) / 2).setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private static Decimal computePercentile(List<Decimal> sortedValues, Integer pct) {
        if (sortedValues.isEmpty()) return 0;
        Integer n = sortedValues.size();
        Decimal rank = (pct / 100.0) * (n - 1);
        Integer lower = (Integer) Math.floor(rank);
        Integer upper = lower + 1;
        if (upper >= n) return sortedValues[n - 1].setScale(2, RoundingMode.HALF_UP);
        Decimal fraction = rank - lower;
        return (sortedValues[lower] + fraction * (sortedValues[upper] - sortedValues[lower]))
            .setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private static Decimal computeAverage(List<Decimal> values) {
        if (values.isEmpty()) return 0;
        Decimal sum = 0;
        for (Decimal v : values) {
            sum += v;
        }
        return (sum / values.size()).setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private static Decimal computeStdDev(List<Decimal> values) {
        if (values.size() < 2) return 0;
        Decimal avg = computeAverage(values);
        Decimal sumSqDiff = 0;
        for (Decimal v : values) {
            Decimal diff = v - avg;
            sumSqDiff += diff * diff;
        }
        Decimal variance = sumSqDiff / values.size();
        Decimal stdDev = Decimal.valueOf(Math.sqrt(variance.doubleValue()));
        return stdDev.setScale(2, RoundingMode.HALF_UP);
    }

    private static String marginToBand(Decimal margin) {
        if (margin >= 25) return '25%+';
        if (margin >= 20) return '20-25%';
        if (margin >= 15) return '15-20%';
        if (margin >= 10) return '10-15%';
        if (margin >= 5) return '5-10%';
        return '0-5%';
    }
}
