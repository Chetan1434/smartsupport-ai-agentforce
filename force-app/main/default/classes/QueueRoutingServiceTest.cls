@IsTest
private class QueueRoutingServiceTest {

    @IsTest
    static void resolvesMappedQueuesInOneCall() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Map<String, Id> resolved = QueueRoutingService.resolve(new Set<String>{ SupportConstants.ROUTE_BILLING, SupportConstants.ROUTE_URGENT });
            Assert.areEqual(2, resolved.size());
            Assert.areEqual(queues.get(SupportConstants.ROUTE_BILLING), resolved.get(SupportConstants.ROUTE_BILLING));
            Assert.areEqual(queues.get(SupportConstants.ROUTE_URGENT), resolved.get(SupportConstants.ROUTE_URGENT));
    
        }
    }

    @IsTest
    static void unmappedKeyAndMissingQueueAreOmittedSafely() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            QueueRoutingService.mappingOverride.put('Ghost', 'Queue_That_Does_Not_Exist');
            QueueRoutingService.mappingOverride.put('Blank', '');
            Map<String, Id> resolved = QueueRoutingService.resolve(new Set<String>{ 'Ghost', 'Blank', 'NotMapped', SupportConstants.ROUTE_GENERAL });
            Assert.areEqual(1, resolved.size(), 'Only the valid mapping may be resolved.');
            Assert.isTrue(resolved.containsKey(SupportConstants.ROUTE_GENERAL));
    
        }
    }

    @IsTest
    static void queueNotEnabledForCaseIsNotUsed() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert new Group(Name = 'SS_Test_NoCase', DeveloperName = 'SS_Test_NoCase', Type = 'Queue'); // no QueueSobject for Case
            }
            QueueRoutingService.mappingOverride = new Map<String, String>{ 'NoCase' => 'SS_Test_NoCase' };
            Assert.isTrue(QueueRoutingService.resolve(new Set<String>{ 'NoCase' }).isEmpty(), 'Assigning a case to such a queue would fail, so it is never returned.');
    
        }
    }

    @IsTest
    static void emptyOrBlankInputReturnsEmptyResult() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isTrue(QueueRoutingService.resolve(null).isEmpty());
            Assert.isTrue(QueueRoutingService.resolve(new Set<String>()).isEmpty());
            Assert.isNull(QueueRoutingService.resolveOne(null));
            Assert.isNull(QueueRoutingService.resolveOne('  '));
    
        }
    }

    @IsTest
    static void resolveOneReturnsQueueId() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Assert.areEqual(queues.get(SupportConstants.ROUTE_SECURITY), QueueRoutingService.resolveOne(SupportConstants.ROUTE_SECURITY));
    
        }
    }

    @IsTest
    static void queueDeveloperNameComesFromCustomMetadataWhenNotOverridden() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            QueueRoutingService.mappingOverride = null;
            Queue_Mapping__mdt billing = Queue_Mapping__mdt.getInstance(SupportConstants.ROUTE_BILLING);
            if (billing == null) {
                return; // the shipped mapping records are not visible in this context (e.g. mid-deployment validation)
            }
            Assert.areEqual(billing.Queue_Developer_Name__c, QueueRoutingService.queueDeveloperName(SupportConstants.ROUTE_BILLING));
            Assert.areEqual('Billing_Support', QueueRoutingService.queueDeveloperName(SupportConstants.ROUTE_BILLING), 'Shipped mapping record.');
            Assert.areEqual('Urgent_Escalations', QueueRoutingService.queueDeveloperName(SupportConstants.ROUTE_URGENT));
            Assert.isNull(QueueRoutingService.queueDeveloperName('Unknown_Key'));
            Assert.isNull(QueueRoutingService.queueDeveloperName(null));
    
        }
    }

    @IsTest
    static void isQueueIdDistinguishesQueuesFromUsers() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Assert.isTrue(QueueRoutingService.isQueueId(queues.get(SupportConstants.ROUTE_BILLING)));
            Assert.isFalse(QueueRoutingService.isQueueId(UserInfo.getUserId()));
            Assert.isFalse(QueueRoutingService.isQueueId(null));
    
        }
    }
}
