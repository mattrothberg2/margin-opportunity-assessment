/**
 * Tests for MOA_Scanner batch analysis engine.
 * Creates realistic test data: 3 accounts, products, and 15 opportunities
 * with varying amounts, stages, and owners.
 */
@IsTest
private class MOA_ScannerTest {

    @TestSetup
    static void setupData() {
        // Config
        MOA_Config__c config = new MOA_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Install_Date__c = Date.today(),
            Scan_Months__c = 24,
            Min_Cohort_Size__c = 2  // Low threshold for test data
        );
        insert config;

        // Accounts: Enterprise, Mid-Market, SMB
        Account enterprise = new Account(
            Name = 'Acme Corp',
            AnnualRevenue = 5000000000.00, // $5B
            Industry = 'Technology',
            NumberOfEmployees = 50000
        );
        Account midMarket = new Account(
            Name = 'Beta Inc',
            AnnualRevenue = 200000000.00,  // $200M
            Industry = 'Manufacturing',
            NumberOfEmployees = 2000
        );
        Account smb = new Account(
            Name = 'Gamma LLC',
            AnnualRevenue = 20000000.00,   // $20M
            Industry = 'Healthcare',
            NumberOfEmployees = 150
        );
        insert new List<Account>{ enterprise, midMarket, smb };

        // Products
        Product2 ciscoProduct = new Product2(
            Name = 'Cisco Catalyst 9300',
            Family = 'Cisco',
            ProductCode = 'C9300-48T',
            IsActive = true
        );
        Product2 dellProduct = new Product2(
            Name = 'Dell PowerEdge R750',
            Family = 'Dell',
            ProductCode = 'PE-R750',
            IsActive = true
        );
        Product2 hpeProduct = new Product2(
            Name = 'HPE ProLiant DL380',
            Family = 'HPE',
            ProductCode = 'HPE-DL380',
            IsActive = true
        );
        insert new List<Product2>{ ciscoProduct, dellProduct, hpeProduct };

        // Standard Pricebook
        Id stdPbId = Test.getStandardPricebookId();

        PricebookEntry ciscoPbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = ciscoProduct.Id,
            UnitPrice = 5000,
            IsActive = true
        );
        PricebookEntry dellPbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = dellProduct.Id,
            UnitPrice = 15000,
            IsActive = true
        );
        PricebookEntry hpePbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = hpeProduct.Id,
            UnitPrice = 12000,
            IsActive = true
        );
        insert new List<PricebookEntry>{ ciscoPbe, dellPbe, hpePbe };

        // Opportunities — mix of Won/Lost across accounts and sizes
        List<Opportunity> opps = new List<Opportunity>();

        // Enterprise account — Cisco deals (5 deals)
        opps.add(createOpp('Enterprise Cisco Deal 1', enterprise.Id, 50000, 'Closed Won', -30));
        opps.add(createOpp('Enterprise Cisco Deal 2', enterprise.Id, 75000, 'Closed Won', -60));
        opps.add(createOpp('Enterprise Cisco Deal 3', enterprise.Id, 60000, 'Closed Lost', -45));
        opps.add(createOpp('Enterprise Cisco Deal 4', enterprise.Id, 120000, 'Closed Won', -90));
        opps.add(createOpp('Enterprise Cisco Deal 5', enterprise.Id, 45000, 'Closed Lost', -15));

        // Mid-Market account — Dell deals (5 deals)
        opps.add(createOpp('MidMarket Dell Deal 1', midMarket.Id, 30000, 'Closed Won', -20));
        opps.add(createOpp('MidMarket Dell Deal 2', midMarket.Id, 55000, 'Closed Won', -50));
        opps.add(createOpp('MidMarket Dell Deal 3', midMarket.Id, 40000, 'Closed Lost', -70));
        opps.add(createOpp('MidMarket Dell Deal 4', midMarket.Id, 25000, 'Closed Won', -100));
        opps.add(createOpp('MidMarket Dell Deal 5', midMarket.Id, 35000, 'Closed Won', -110));

        // SMB account — HPE deals (5 deals)
        opps.add(createOpp('SMB HPE Deal 1', smb.Id, 15000, 'Closed Won', -10));
        opps.add(createOpp('SMB HPE Deal 2', smb.Id, 20000, 'Closed Lost', -25));
        opps.add(createOpp('SMB HPE Deal 3', smb.Id, 18000, 'Closed Won', -55));
        opps.add(createOpp('SMB HPE Deal 4', smb.Id, 22000, 'Closed Won', -80));
        opps.add(createOpp('SMB HPE Deal 5', smb.Id, 12000, 'Closed Lost', -95));

        for (Opportunity o : opps) {
            o.Pricebook2Id = stdPbId;
        }
        insert opps;

        // Line items — assign products to match OEM pattern
        List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
        for (Integer i = 0; i < 5; i++) {
            olis.add(new OpportunityLineItem(
                OpportunityId = opps[i].Id,
                PricebookEntryId = ciscoPbe.Id,
                Quantity = Math.max(1, Math.round(opps[i].Amount / 5000)),
                UnitPrice = 5000
            ));
        }
        for (Integer i = 5; i < 10; i++) {
            olis.add(new OpportunityLineItem(
                OpportunityId = opps[i].Id,
                PricebookEntryId = dellPbe.Id,
                Quantity = Math.max(1, Math.round(opps[i].Amount / 15000)),
                UnitPrice = 15000
            ));
        }
        for (Integer i = 10; i < 15; i++) {
            olis.add(new OpportunityLineItem(
                OpportunityId = opps[i].Id,
                PricebookEntryId = hpePbe.Id,
                Quantity = Math.max(1, Math.round(opps[i].Amount / 12000)),
                UnitPrice = 12000
            ));
        }
        insert olis;
    }

    private static Opportunity createOpp(String name, Id accountId, Decimal amount, String stage, Integer daysOffset) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            StageName = stage,
            CloseDate = Date.today().addDays(daysOffset)
        );
    }

    // ── Batch integration test ──

    @IsTest
    static void testFullBatchScan() {
        Test.startTest();
        MOA_Scanner scanner = new MOA_Scanner(24, 2);
        Database.executeBatch(scanner, 200);
        Test.stopTest();

        List<MOA_Scan_Result__c> records = [
            SELECT Result_JSON__c, Scan_Status__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!records.isEmpty(), 'Scan result record should exist');
        MOA_Scan_Result__c record = records[0];
        System.assertEquals('Complete', record.Scan_Status__c, 'Scan should complete successfully');
        System.assertNotEquals(null, record.Result_JSON__c, 'Result JSON should be populated');

        MOA_Models.ScanResult result = (MOA_Models.ScanResult) JSON.deserialize(
            record.Result_JSON__c, MOA_Models.ScanResult.class
        );

        System.assertEquals(15, result.totalDeals, 'Should find 15 deals');
        System.assertEquals(10, result.totalWon, 'Should find 10 won deals');
        System.assertEquals(5, result.totalLost, 'Should find 5 lost deals');
        System.assert(result.totalRevenue > 0, 'Total revenue should be positive');
        System.assertNotEquals(null, result.cohorts, 'Cohorts should be populated');
        System.assert(!result.cohorts.isEmpty(), 'Should have at least one cohort');
        System.assertNotEquals(null, result.reps, 'Reps should be populated');
        System.assertNotEquals(null, result.winRateByMarginBand, 'Margin bands should be populated');
        System.assertEquals(6, result.winRateByMarginBand.size(), 'Should have 6 margin bands');
        System.assertEquals(24, result.scanMonths, 'Scan months should be 24');
    }

    // ── Cohort structure test ──

    @IsTest
    static void testCohortStructure() {
        Test.startTest();
        MOA_Scanner scanner = new MOA_Scanner(24, 2);
        Database.executeBatch(scanner, 200);
        Test.stopTest();

        List<MOA_Scan_Result__c> records = [
            SELECT Result_JSON__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!records.isEmpty(), 'Scan result record should exist');
        MOA_Models.ScanResult result = (MOA_Models.ScanResult) JSON.deserialize(
            records[0].Result_JSON__c, MOA_Models.ScanResult.class
        );

        for (MOA_Models.Cohort cohort : result.cohorts) {
            System.assertNotEquals(null, cohort.oem, 'Cohort OEM should be set');
            System.assertNotEquals(null, cohort.sizeBucket, 'Cohort size bucket should be set');
            System.assertNotEquals(null, cohort.segment, 'Cohort segment should be set');
            System.assert(cohort.dealCount >= 2, 'Cohort should meet min size: ' + cohort.dealCount);
            System.assert(cohort.winRate >= 0 && cohort.winRate <= 100,
                'Win rate should be 0-100: ' + cohort.winRate);
        }
    }

    // ── OEM derivation ──

    @IsTest
    static void testDeriveOem() {
        // Create test opportunity with Cisco product
        Account a = [SELECT Id FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        Opportunity opp = [
            SELECT Id, Name, Amount, StageName, CloseDate, OwnerId, IsWon,
                   Account.Industry, Account.AnnualRevenue, Account.NumberOfEmployees,
                   Account.Name, Owner.Name,
                   (SELECT ProductCode, UnitPrice, Quantity, TotalPrice,
                           Product2.Family, Product2.Name FROM OpportunityLineItems)
            FROM Opportunity
            WHERE AccountId = :a.Id AND StageName = 'Closed Won'
            LIMIT 1
        ];

        String oem = MOA_Scanner.deriveOem(opp);
        System.assertEquals('Cisco', oem, 'Should detect Cisco from product family');
    }

    // ── Size bucket derivation ──

    @IsTest
    static void testDeriveSizeBucket() {
        System.assertEquals('<$25K', MOA_Scanner.deriveSizeBucket(10000));
        System.assertEquals('$25K-100K', MOA_Scanner.deriveSizeBucket(50000));
        System.assertEquals('$100K-500K', MOA_Scanner.deriveSizeBucket(200000));
        System.assertEquals('$500K-1M', MOA_Scanner.deriveSizeBucket(750000));
        System.assertEquals('$1M+', MOA_Scanner.deriveSizeBucket(2000000));
        System.assertEquals('Unknown', MOA_Scanner.deriveSizeBucket(null));
    }

    // ── Customer segment derivation ──

    @IsTest
    static void testDeriveSegment() {
        System.assertEquals('Enterprise', MOA_Scanner.deriveSegment(5000000000.00));
        System.assertEquals('Mid-Market', MOA_Scanner.deriveSegment(200000000.00));
        System.assertEquals('SMB', MOA_Scanner.deriveSegment(20000000.00));
        System.assertEquals('Unknown', MOA_Scanner.deriveSegment(5000000.00));
        System.assertEquals('Unknown', MOA_Scanner.deriveSegment(null));
    }

    // ── Math helpers ──

    @IsTest
    static void testComputeMedian() {
        // Odd count
        List<Decimal> odd = new List<Decimal>{ 1, 3, 5, 7, 9 };
        System.assertEquals(5.00, MOA_Scanner.computeMedian(odd));

        // Even count
        List<Decimal> even = new List<Decimal>{ 1, 3, 5, 7 };
        System.assertEquals(4.00, MOA_Scanner.computeMedian(even));

        // Single value
        List<Decimal> single = new List<Decimal>{ 42 };
        System.assertEquals(42.00, MOA_Scanner.computeMedian(single));

        // Empty
        List<Decimal> empty = new List<Decimal>();
        System.assertEquals(0, MOA_Scanner.computeMedian(empty));
    }

    @IsTest
    static void testComputePercentile() {
        List<Decimal> values = new List<Decimal>{ 10, 20, 30, 40, 50 };
        Decimal p25 = MOA_Scanner.computePercentile(values, 25);
        Decimal p75 = MOA_Scanner.computePercentile(values, 75);
        System.assert(p25 >= 10 && p25 <= 30, 'P25 should be between 10 and 30: ' + p25);
        System.assert(p75 >= 30 && p75 <= 50, 'P75 should be between 30 and 50: ' + p75);
    }

    @IsTest
    static void testComputeAverage() {
        List<Decimal> values = new List<Decimal>{ 10, 20, 30 };
        System.assertEquals(20.00, MOA_Scanner.computeAverage(values));

        System.assertEquals(0, MOA_Scanner.computeAverage(new List<Decimal>()));
    }

    @IsTest
    static void testComputeStdDev() {
        // All same values => stddev = 0
        List<Decimal> same = new List<Decimal>{ 5, 5, 5, 5 };
        System.assertEquals(0.00, MOA_Scanner.computeStdDev(same));

        // Known values: [2, 4, 4, 4, 5, 5, 7, 9] => mean=5, stddev=2
        List<Decimal> known = new List<Decimal>{ 2, 4, 4, 4, 5, 5, 7, 9 };
        Decimal sd = MOA_Scanner.computeStdDev(known);
        System.assert(sd >= 1.5 && sd <= 2.5, 'StdDev should be ~2: ' + sd);

        // Single value
        System.assertEquals(0, MOA_Scanner.computeStdDev(new List<Decimal>{ 42 }));
    }

    // ── Config last scan date updated ──

    @IsTest
    static void testConfigUpdatedAfterScan() {
        MOA_Config__c configBefore = MOA_Config__c.getOrgDefaults();
        Datetime before = configBefore.Last_Scan_Date__c;

        Test.startTest();
        MOA_Scanner scanner = new MOA_Scanner(24, 2);
        Database.executeBatch(scanner, 200);
        Test.stopTest();

        MOA_Config__c configAfter = MOA_Config__c.getOrgDefaults();
        System.assertNotEquals(null, configAfter.Last_Scan_Date__c,
            'Last scan date should be set after scan');
        if (before != null) {
            System.assert(configAfter.Last_Scan_Date__c >= before,
                'Last scan date should be updated');
        }
    }

    // ── Edge case: no deals ──

    @IsTest
    static void testScanWithNoDeals() {
        // Delete all opportunities
        delete [SELECT Id FROM Opportunity];

        Test.startTest();
        MOA_Scanner scanner = new MOA_Scanner(24, 2);
        Database.executeBatch(scanner, 200);
        Test.stopTest();

        List<MOA_Scan_Result__c> records = [
            SELECT Result_JSON__c, Scan_Status__c FROM MOA_Scan_Result__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!records.isEmpty(), 'Scan result record should exist');
        MOA_Scan_Result__c record = records[0];
        System.assertEquals('Complete', record.Scan_Status__c, 'Should complete even with no deals');

        MOA_Models.ScanResult result = (MOA_Models.ScanResult) JSON.deserialize(
            record.Result_JSON__c, MOA_Models.ScanResult.class
        );
        System.assertEquals(0, result.totalDeals, 'Should have 0 deals');
        System.assert(result.cohorts.isEmpty(), 'Should have no cohorts');
    }
}
