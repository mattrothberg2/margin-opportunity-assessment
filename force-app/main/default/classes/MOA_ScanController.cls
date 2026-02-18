/**
 * Controller for the MOA Dashboard LWC.
 * Provides AuraEnabled methods to trigger batch scans and retrieve results.
 */
public with sharing class MOA_ScanController {

    /**
     * Start an asynchronous scan. Sets status to Running and kicks off batch.
     * @return The batch job Id
     */
    @AuraEnabled
    public static String startScan() {
        MOA_Config__c config = MOA_Config__c.getInstance();
        Integer scanMonths = config != null && config.Scan_Months__c != null
            ? Integer.valueOf(config.Scan_Months__c)
            : 24;
        Integer minCohortSize = config != null && config.Min_Cohort_Size__c != null
            ? Integer.valueOf(config.Min_Cohort_Size__c)
            : 5;

        // Mark as running — use singleton record pattern
        MOA_Scan_Result__c record = getOrCreateResultRecord();
        record.Scan_Status__c = 'Running';
        record.Error_Message__c = null;
        record.Scan_Date__c = Datetime.now();
        upsert record;

        MOA_Scanner scanner = new MOA_Scanner(scanMonths, minCohortSize);
        Id batchId = Database.executeBatch(scanner, 200);
        return String.valueOf(batchId);
    }

    /**
     * Get the most recent scan result JSON.
     * @return JSON-serialized ScanResult or null if no scan exists
     */
    @AuraEnabled(cacheable=true)
    public static String getScanResult() {
        List<MOA_Scan_Result__c> records = [
            SELECT Result_JSON__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (records.isEmpty() || String.isBlank(records[0].Result_JSON__c)) {
            return null;
        }
        return records[0].Result_JSON__c;
    }

    /**
     * Get the current scan status.
     * @return Status string: Running, Running: X/Y, Complete, Error, or null
     */
    @AuraEnabled
    public static String getScanStatus() {
        List<MOA_Scan_Result__c> records = [
            SELECT Scan_Status__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (records.isEmpty()) {
            return null;
        }
        return records[0].Scan_Status__c;
    }

    /**
     * Get scan configuration values.
     * @return Map of config key/value pairs
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getConfig() {
        MOA_Config__c config = MOA_Config__c.getInstance();
        Map<String, Object> configMap = new Map<String, Object>();
        configMap.put('scanMonths', config != null && config.Scan_Months__c != null ? config.Scan_Months__c : 24);
        configMap.put('minCohortSize', config != null && config.Min_Cohort_Size__c != null ? config.Min_Cohort_Size__c : 5);
        configMap.put('lastScanDate', config != null ? config.Last_Scan_Date__c : null);
        configMap.put('installDate', config != null ? config.Install_Date__c : null);
        return configMap;
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
}
