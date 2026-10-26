@IsTest
private class CustomerContextServiceTest {

    @IsTest
    static void premiumAccountIdsReturnsOnlyPremiumAccounts() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Account premium = SupportTestDataFactory.createAccount('Premium Co', 'Premium');
            Account standard = SupportTestDataFactory.createAccount('Standard Co', 'Standard');
            Set<Id> result = CustomerContextService.premiumAccountIds(new Set<Id>{ premium.Id, standard.Id });
            Assert.areEqual(1, result.size());
            Assert.isTrue(result.contains(premium.Id));
    
        }
    }

    @IsTest
    static void premiumAccountIdsHandlesNullAndEmpty() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isTrue(CustomerContextService.premiumAccountIds(null).isEmpty());
            Assert.isTrue(CustomerContextService.premiumAccountIds(new Set<Id>()).isEmpty());
    
        }
    }

    @IsTest
    static void getContextReturnsMinimalCustomerData() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Account a = SupportTestDataFactory.createAccount('Premium Co', 'Premium');
            Contact contact = SupportTestDataFactory.createContact(a.Id, 'Rao', 'rao@example.com');
            Case c = SupportTestDataFactory.buildCase('Invoice', 'billing');
            c.AccountId = a.Id;
            c.ContactId = contact.Id;
            insert c;
            insert SupportTestDataFactory.buildCase('Second', 'general') ;

            CustomerContextService.CustomerContext context = CustomerContextService.getContext(c.Id);
            Assert.areEqual('Premium Co', context.accountName);
            Assert.areEqual('Premium', context.supportTier);
            Assert.areEqual('Rao', context.contactName);
            Assert.areEqual(1, context.openCasesForAccount, 'Only open cases of the same account are counted.');
    
        }
    }

    @IsTest
    static void getContextWithoutCaseOrAccessIsEmptyNotAnError() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isNull(CustomerContextService.getContext(null).accountName);
            Case c = SupportTestDataFactory.createCase('x', 'y');
            delete c;
            Assert.isNull(CustomerContextService.getContext(c.Id).accountName);

            Case other = SupportTestDataFactory.createCase('x', 'y');
            User noAccess = SupportTestDataFactory.createNoAccessUser();
            if (noAccess != null) {
                System.runAs(noAccess) {
                    Assert.isNull(CustomerContextService.getContext(other.Id).accountName, 'No data may be returned without access.');
                }
            }
    
        }
    }
}
