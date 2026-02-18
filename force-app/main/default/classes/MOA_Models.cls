/**
 * Data classes for MOA scan results.
 * No proprietary logic — plain statistics containers.
 */
public with sharing class MOA_Models {

    public class Cohort {
        @AuraEnabled public String oem { get; set; }
        @AuraEnabled public String sizeBucket { get; set; }
        @AuraEnabled public String segment { get; set; }
        @AuraEnabled public Integer dealCount { get; set; }
        @AuraEnabled public Integer wonCount { get; set; }
        @AuraEnabled public Integer lostCount { get; set; }
        @AuraEnabled public Decimal winRate { get; set; }
        @AuraEnabled public Decimal medianMargin { get; set; }
        @AuraEnabled public Decimal p25Margin { get; set; }
        @AuraEnabled public Decimal p75Margin { get; set; }
        @AuraEnabled public Decimal avgMargin { get; set; }
        @AuraEnabled public Decimal totalRevenue { get; set; }
        @AuraEnabled public Decimal marginOpportunity { get; set; }
    }

    public class RepStats {
        @AuraEnabled public String repName { get; set; }
        @AuraEnabled public String repId { get; set; }
        @AuraEnabled public Integer dealCount { get; set; }
        @AuraEnabled public Integer wonCount { get; set; }
        @AuraEnabled public Decimal avgMargin { get; set; }
        @AuraEnabled public Decimal vsTeamAvg { get; set; }
        @AuraEnabled public Decimal consistency { get; set; }
        @AuraEnabled public Decimal marginLeftOnTable { get; set; }
    }

    public class MarginBand {
        @AuraEnabled public String band { get; set; }
        @AuraEnabled public Integer dealCount { get; set; }
        @AuraEnabled public Decimal winRate { get; set; }
    }

    public class ScanResult {
        @AuraEnabled public Integer totalDeals { get; set; }
        @AuraEnabled public Integer totalWon { get; set; }
        @AuraEnabled public Integer totalLost { get; set; }
        @AuraEnabled public Decimal totalRevenue { get; set; }
        @AuraEnabled public Decimal currentAvgMargin { get; set; }
        @AuraEnabled public Decimal achievableAvgMargin { get; set; }
        @AuraEnabled public Decimal annualOpportunity { get; set; }
        @AuraEnabled public List<Cohort> cohorts { get; set; }
        @AuraEnabled public List<RepStats> reps { get; set; }
        @AuraEnabled public List<MarginBand> winRateByMarginBand { get; set; }
        @AuraEnabled public Datetime scanDate { get; set; }
        @AuraEnabled public Integer scanMonths { get; set; }
    }
}
