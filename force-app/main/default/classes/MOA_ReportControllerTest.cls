/**
 * Tests for MOA_ReportController (PDF export).
 */
@IsTest
private class MOA_ReportControllerTest {

    @IsTest
    static void testWithScanResult() {
        // Create a mock scan result
        MOA_Models.ScanResult mockResult = new MOA_Models.ScanResult();
        mockResult.totalDeals = 100;
        mockResult.totalWon = 65;
        mockResult.totalLost = 35;
        mockResult.totalRevenue = 5000000;
        mockResult.currentAvgMargin = 12.5;
        mockResult.achievableAvgMargin = 16.8;
        mockResult.annualOpportunity = 215000;
        mockResult.scanDate = Datetime.now();
        mockResult.scanMonths = 24;

        MOA_Models.Cohort c = new MOA_Models.Cohort();
        c.oem = 'Cisco';
        c.sizeBucket = '$25K-100K';
        c.segment = 'Enterprise';
        c.dealCount = 20;
        c.wonCount = 14;
        c.lostCount = 6;
        c.winRate = 70.0;
        c.medianMargin = 15.0;
        c.avgMargin = 12.0;
        c.marginOpportunity = 45000;
        mockResult.cohorts = new List<MOA_Models.Cohort>{ c };

        MOA_Models.RepStats r = new MOA_Models.RepStats();
        r.repName = 'Test Rep';
        r.repId = '005000000000001';
        r.dealCount = 10;
        r.wonCount = 7;
        r.avgMargin = 14.0;
        r.vsTeamAvg = 1.5;
        r.consistency = 3.2;
        r.marginLeftOnTable = 12000;
        mockResult.reps = new List<MOA_Models.RepStats>{ r };

        mockResult.winRateByMarginBand = new List<MOA_Models.MarginBand>();

        MOA_Scan_Result__c record = new MOA_Scan_Result__c(
            Result_JSON__c = JSON.serialize(mockResult),
            Scan_Status__c = 'Complete',
            Scan_Date__c = Datetime.now()
        );
        insert record;

        Test.startTest();
        MOA_ReportController ctrl = new MOA_ReportController();
        Test.stopTest();

        System.assertEquals(100, ctrl.result.totalDeals);
        System.assertNotEquals(null, ctrl.formattedAnnualOpportunity);
        System.assertNotEquals(null, ctrl.scanDateFormatted);
        System.assertEquals(1, ctrl.topCohorts.size());
        System.assertEquals(1, ctrl.sortedReps.size());
        System.assertEquals(1, ctrl.cohortCount);
        System.assertEquals(1, ctrl.repCount);
    }

    @IsTest
    static void testWithNoResult() {
        Test.startTest();
        MOA_ReportController ctrl = new MOA_ReportController();
        Test.stopTest();

        System.assertEquals(0, ctrl.result.totalDeals);
        System.assert(ctrl.topCohorts.isEmpty());
        System.assert(ctrl.sortedReps.isEmpty());
    }
}
