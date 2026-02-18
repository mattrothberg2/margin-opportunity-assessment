/**
 * Tests for MOA_ScanController.
 */
@IsTest
private class MOA_ScanControllerTest {

    @TestSetup
    static void setupConfig() {
        MOA_Config__c config = new MOA_Config__c(
            SetupOwnerId = UserInfo.getUserId(),
            Install_Date__c = Date.today(),
            Scan_Months__c = 24,
            Min_Cohort_Size__c = 5
        );
        insert config;
    }

    @IsTest
    static void testRunScan() {
        Test.startTest();
        String resultJson = MOA_ScanController.runScan();
        Test.stopTest();

        System.assertNotEquals(null, resultJson, 'Should return JSON result');

        MOA_Models.ScanResult result = (MOA_Models.ScanResult) JSON.deserialize(
            resultJson, MOA_Models.ScanResult.class
        );
        System.assertNotEquals(null, result, 'Should deserialize to ScanResult');

        // Verify persisted
        MOA_Scan_Result__c record = MOA_Scan_Result__c.getInstance();
        System.assertEquals('Complete', record.Scan_Status__c, 'Status should be Complete');
    }

    @IsTest
    static void testGetLastScanResultEmpty() {
        String result = MOA_ScanController.getLastScanResult();
        // No scan has been run yet — may be null or empty
        // This is acceptable behavior
        System.assert(result == null || result == '', 'Should be null or empty when no scan exists');
    }

    @IsTest
    static void testGetLastScanResultAfterScan() {
        MOA_ScanController.runScan();

        Test.startTest();
        String result = MOA_ScanController.getLastScanResult();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return last scan result');
    }

    @IsTest
    static void testGetConfig() {
        Test.startTest();
        Map<String, Object> config = MOA_ScanController.getConfig();
        Test.stopTest();

        System.assertNotEquals(null, config, 'Config should not be null');
        System.assertEquals(24, (Decimal) config.get('scanMonths'), 'Default scan months should be 24');
        System.assertEquals(5, (Decimal) config.get('minCohortSize'), 'Default min cohort size should be 5');
    }
}
