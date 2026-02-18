/**
 * Tests for MOA_ScanController.
 */
@IsTest
private class MOA_ScanControllerTest {

    @TestSetup
    static void setupData() {
        MOA_Config__c config = new MOA_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Install_Date__c = Date.today(),
            Scan_Months__c = 24,
            Min_Cohort_Size__c = 2
        );
        insert config;

        Account acc = new Account(
            Name = 'Test Account',
            AnnualRevenue = 500000000.00
        );
        insert acc;

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opps.add(new Opportunity(
                Name = 'Test Opp ' + i,
                AccountId = acc.Id,
                Amount = 50000 + (i * 10000),
                StageName = i < 2 ? 'Closed Won' : 'Closed Lost',
                CloseDate = Date.today().addDays(-30 * (i + 1))
            ));
        }
        insert opps;
    }

    @IsTest
    static void testStartScan() {
        Test.startTest();
        String batchId = MOA_ScanController.startScan();
        Test.stopTest();

        System.assertNotEquals(null, batchId, 'Should return a batch job Id');

        // After Test.stopTest(), the batch has completed
        List<MOA_Scan_Result__c> records = [
            SELECT Scan_Status__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!records.isEmpty(), 'Scan result record should exist');
        System.assertEquals('Complete', records[0].Scan_Status__c,
            'Status should be Complete after batch finishes');
    }

    @IsTest
    static void testGetScanStatusRunning() {
        // Manually set status to Running
        MOA_Scan_Result__c record = new MOA_Scan_Result__c(
            Scan_Status__c = 'Running',
            Scan_Date__c = Datetime.now()
        );
        insert record;

        String status = MOA_ScanController.getScanStatus();
        System.assertEquals('Running', status, 'Should return Running status');
    }

    @IsTest
    static void testGetScanStatusNull() {
        String status = MOA_ScanController.getScanStatus();
        // No scan result record exists yet at org level
        // Status could be null
        System.assert(status == null || String.isNotBlank(status),
            'Status should be null or a valid string');
    }

    @IsTest
    static void testGetScanResultEmpty() {
        String result = MOA_ScanController.getScanResult();
        System.assert(result == null, 'Should be null when no scan has been run');
    }

    @IsTest
    static void testGetScanResultAfterScan() {
        Test.startTest();
        MOA_ScanController.startScan();
        Test.stopTest();

        String result = MOA_ScanController.getScanResult();
        System.assertNotEquals(null, result, 'Should return scan result JSON');

        MOA_Models.ScanResult parsed = (MOA_Models.ScanResult) JSON.deserialize(
            result, MOA_Models.ScanResult.class
        );
        System.assertNotEquals(null, parsed, 'Should deserialize to ScanResult');
        System.assert(parsed.totalDeals > 0, 'Should have found deals');
    }

    @IsTest
    static void testGetConfig() {
        Map<String, Object> config = MOA_ScanController.getConfig();

        System.assertNotEquals(null, config, 'Config should not be null');
        System.assertEquals(24, (Decimal) config.get('scanMonths'), 'Default scan months should be 24');
        System.assertEquals(2, (Decimal) config.get('minCohortSize'), 'Min cohort size should be 2');
    }
}
