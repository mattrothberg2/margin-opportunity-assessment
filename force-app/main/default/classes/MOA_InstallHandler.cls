/**
 * Post-install handler for MOA package.
 * Sets default configuration values on first install.
 */
global class MOA_InstallHandler implements InstallHandler {

    global void onInstall(InstallContext context) {
        if (context.previousVersion() == null) {
            // Fresh install — set defaults
            setDefaults();
        }
    }

    @TestVisible
    private static void setDefaults() {
        MOA_Config__c config = MOA_Config__c.getOrgDefaults();
        if (config.Id == null) {
            config = new MOA_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        config.Install_Date__c = Date.today();
        config.Scan_Months__c = 24;
        config.Min_Cohort_Size__c = 5;
        upsert config;
    }
}
