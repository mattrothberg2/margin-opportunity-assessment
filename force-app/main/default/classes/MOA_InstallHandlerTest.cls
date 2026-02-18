/**
 * Tests for MOA_InstallHandler.
 */
@IsTest
private class MOA_InstallHandlerTest {

    @IsTest
    static void testSetDefaults() {
        Test.startTest();
        MOA_InstallHandler.setDefaults();
        Test.stopTest();

        MOA_Config__c config = MOA_Config__c.getOrgDefaults();
        System.assertNotEquals(null, config.Id, 'Config record should be created');
        System.assertEquals(Date.today(), config.Install_Date__c, 'Install date should be today');
        System.assertEquals(24, config.Scan_Months__c, 'Scan months should default to 24');
        System.assertEquals(5, config.Min_Cohort_Size__c, 'Min cohort size should default to 5');
    }

    @IsTest
    static void testOnInstallFreshInstall() {
        MOA_InstallHandler handler = new MOA_InstallHandler();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        MOA_Config__c config = MOA_Config__c.getOrgDefaults();
        System.assertNotEquals(null, config.Id, 'Config should be created on fresh install');
        System.assertEquals(24, config.Scan_Months__c, 'Should set default scan months');
    }

    @IsTest
    static void testOnInstallUpgrade() {
        // Pre-existing config
        MOA_Config__c existing = new MOA_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Install_Date__c = Date.today().addDays(-30),
            Scan_Months__c = 12,
            Min_Cohort_Size__c = 3
        );
        insert existing;

        MOA_InstallHandler handler = new MOA_InstallHandler();

        Test.startTest();
        Test.testInstall(handler, new Version(1, 0));
        Test.stopTest();

        // Upgrade should NOT overwrite existing config
        MOA_Config__c config = MOA_Config__c.getOrgDefaults();
        System.assertEquals(12, config.Scan_Months__c, 'Upgrade should not overwrite existing config');
    }
}
