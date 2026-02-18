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

        // Mark as running
        MOA_Scan_Result__c record = MOA_Scan_Result__c.getOrgDefaults();
        if (record.Id == null) {
            record = new MOA_Scan_Result__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
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
        MOA_Scan_Result__c record = MOA_Scan_Result__c.getOrgDefaults();
        if (record == null || record.Id == null || String.isBlank(record.Result_JSON__c)) {
            return null;
        }
        return record.Result_JSON__c;
    }

    /**
     * Get the current scan status.
     * @return Status string: Running, Complete, Error, or null
     */
    @AuraEnabled
    public static String getScanStatus() {
        MOA_Scan_Result__c record = MOA_Scan_Result__c.getOrgDefaults();
        if (record == null || record.Id == null) {
            return null;
        }
        return record.Scan_Status__c;
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
}
