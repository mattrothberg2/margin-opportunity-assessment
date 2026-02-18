/**
 * Controller for the MOA Dashboard LWC.
 * Provides AuraEnabled methods to trigger scans and retrieve results.
 */
public with sharing class MOA_ScanController {

    /**
     * Run a new scan using config defaults or provided parameters.
     * @return JSON-serialized ScanResult
     */
    @AuraEnabled
    public static String runScan() {
        MOA_Config__c config = MOA_Config__c.getInstance();
        Integer scanMonths = config.Scan_Months__c != null
            ? Integer.valueOf(config.Scan_Months__c)
            : 24;
        Integer minCohortSize = config.Min_Cohort_Size__c != null
            ? Integer.valueOf(config.Min_Cohort_Size__c)
            : 5;

        MOA_Models.ScanResult result = MOA_Scanner.runScan(scanMonths, minCohortSize);

        String resultJson = JSON.serialize(result);

        // Persist the result
        MOA_Scan_Result__c record = MOA_Scan_Result__c.getInstance();
        if (record == null) {
            record = new MOA_Scan_Result__c(SetupOwnerId = UserInfo.getUserId());
        }
        record.Result_JSON__c = resultJson;
        record.Scan_Status__c = 'Complete';
        record.Error_Message__c = null;
        record.Scan_Date__c = Datetime.now();
        upsert record;

        // Update last scan date in config
        config.Last_Scan_Date__c = Datetime.now();
        upsert config;

        return resultJson;
    }

    /**
     * Get the most recent scan result without re-running.
     * @return JSON-serialized ScanResult or null if no scan exists
     */
    @AuraEnabled(cacheable=true)
    public static String getLastScanResult() {
        MOA_Scan_Result__c record = MOA_Scan_Result__c.getInstance();
        if (record == null || String.isBlank(record.Result_JSON__c)) {
            return null;
        }
        return record.Result_JSON__c;
    }

    /**
     * Get scan configuration values.
     * @return Map of config key/value pairs
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getConfig() {
        MOA_Config__c config = MOA_Config__c.getInstance();
        Map<String, Object> configMap = new Map<String, Object>();
        configMap.put('scanMonths', config.Scan_Months__c != null ? config.Scan_Months__c : 24);
        configMap.put('minCohortSize', config.Min_Cohort_Size__c != null ? config.Min_Cohort_Size__c : 5);
        configMap.put('lastScanDate', config.Last_Scan_Date__c);
        configMap.put('installDate', config.Install_Date__c);
        return configMap;
    }
}
