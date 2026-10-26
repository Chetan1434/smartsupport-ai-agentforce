@IsTest
private class CaseRoutingRulesTest {

    private static CaseRoutingRules.Decision eval(String subject, String description) {
        CaseRoutingRules.Input input = new CaseRoutingRules.Input();
        input.subject = subject;
        input.description = description;
        return CaseRoutingRules.evaluate(input);
    }

    @IsTest
    static void billingIssueIsCategorizedAsBilling() {
        CaseRoutingRules.Decision d = eval('Double charge on my invoice', 'I was charged twice for the same subscription.');
        Assert.areEqual(SupportConstants.CAT_BILLING, d.category);
        Assert.areEqual(SupportConstants.ROUTE_BILLING, d.routeKey);
        Assert.areEqual(SupportConstants.PRIORITY_MEDIUM, d.recommendedPriority);
        Assert.isFalse(d.mustEscalate(), 'A normal billing question must not escalate.');
        Assert.isFalse(d.signals.isEmpty(), 'The matched keywords must be explainable.');
    }

    @IsTest
    static void invoicePluralMatchesPrefixRule() {
        Assert.areEqual(SupportConstants.CAT_BILLING, eval('Missing invoices', 'Please send them').category);
    }

    @IsTest
    static void loginProblemIsAccountAccessNotTechnical() {
        CaseRoutingRules.Decision d = eval('Cannot log in', 'I forgot my password and the reset email never arrives. There is an error page.');
        Assert.areEqual(SupportConstants.CAT_ACCESS, d.category, 'Account access wins over a generic technical keyword.');
        Assert.areEqual(SupportConstants.ROUTE_ACCESS, d.routeKey);
    }

    @IsTest
    static void widespreadOutageIsUrgentAndRoutedToUrgentQueueKey() {
        CaseRoutingRules.Decision d = eval('Service is down for all users', 'Nobody can open the dashboard since 9am.');
        Assert.isTrue(d.outageSuspected);
        Assert.isTrue(d.isUrgentByRule());
        Assert.areEqual(SupportConstants.CAT_TECHNICAL, d.category);
        Assert.areEqual(SupportConstants.PRIORITY_HIGH, d.recommendedPriority);
        Assert.areEqual(SupportConstants.REASON_OUTAGE, d.escalationReason);
        Assert.areEqual(SupportConstants.ROUTE_URGENT, d.escalationRouteKey);
    }

    @IsTest
    static void securityConcernFollowsSecurityEscalationPath() {
        CaseRoutingRules.Decision d = eval('Unauthorized access to our account', 'Someone else logged in and changed our settings.');
        Assert.isTrue(d.securityConcern);
        Assert.areEqual(SupportConstants.CAT_SECURITY, d.category);
        Assert.areEqual(SupportConstants.PRIORITY_HIGH, d.recommendedPriority);
        Assert.areEqual(SupportConstants.REASON_SECURITY, d.escalationReason);
        Assert.areEqual(SupportConstants.ROUTE_SECURITY, d.escalationRouteKey);
        Assert.isTrue(d.suggestedAction.contains('Never ask for passwords'));
    }

    @IsTest
    static void securityTakesPrecedenceOverOutage() {
        CaseRoutingRules.Decision d = eval('Data breach', 'Our entire team is affected and the service is down.');
        Assert.areEqual(SupportConstants.REASON_SECURITY, d.escalationReason);
        Assert.areEqual(SupportConstants.CAT_SECURITY, d.category);
    }

    @IsTest
    static void customerAskingForHumanTriggersHandoffInCategoryQueue() {
        CaseRoutingRules.Decision d = eval('Invoice question', 'I want to talk to a human about my invoice please.');
        Assert.isTrue(d.humanRequested);
        Assert.areEqual(SupportConstants.REASON_HUMAN, d.escalationReason);
        Assert.areEqual(SupportConstants.CAT_BILLING, d.category);
        Assert.areEqual(SupportConstants.ROUTE_BILLING, d.escalationRouteKey, 'A human request stays in the category queue.');
    }

    @IsTest
    static void repeatedFailureTriggersHandoffOnlyAtThreshold() {
        CaseRoutingRules.Input input = new CaseRoutingRules.Input();
        input.subject = 'Question about my order';
        input.description = 'Just checking something.';
        input.failedAttemptThreshold = 2;

        input.failedAttempts = 1;
        Assert.isFalse(CaseRoutingRules.evaluate(input).mustEscalate(), 'One failed attempt is below the threshold.');

        input.failedAttempts = 2;
        CaseRoutingRules.Decision d = CaseRoutingRules.evaluate(input);
        Assert.isTrue(d.repeatedFailure);
        Assert.areEqual(SupportConstants.REASON_AI_FAILURE, d.escalationReason);
    }

    @IsTest
    static void invalidThresholdFallsBackToTwo() {
        CaseRoutingRules.Input input = new CaseRoutingRules.Input();
        input.subject = 'Hello';
        input.failedAttempts = 2;
        input.failedAttemptThreshold = 0;
        Assert.isTrue(CaseRoutingRules.evaluate(input).repeatedFailure);
    }

    @IsTest
    static void negativeSentimentRaisesRecommendationAndPremiumHighPriorityEscalates() {
        CaseRoutingRules.Input input = new CaseRoutingRules.Input();
        input.subject = 'Terrible billing error';
        input.description = 'I am furious about this.';

        CaseRoutingRules.Decision standard = CaseRoutingRules.evaluate(input);
        Assert.areEqual(SupportConstants.SENT_NEGATIVE, standard.sentiment);
        Assert.areEqual(SupportConstants.PRIORITY_HIGH, standard.recommendedPriority, 'Medium + negative sentiment becomes High.');
        Assert.isFalse(standard.mustEscalate(), 'A standard account is not escalated for a High recommendation.');
        Assert.isFalse(standard.isUrgentByRule(), 'A recommendation alone must not be an urgent-by-rule signal.');

        input.premiumAccount = true;
        CaseRoutingRules.Decision premium = CaseRoutingRules.evaluate(input);
        Assert.areEqual(SupportConstants.REASON_PREMIUM, premium.escalationReason);
        Assert.areEqual(SupportConstants.ROUTE_URGENT, premium.escalationRouteKey);
    }

    @IsTest
    static void sentimentPositiveNeutralAndUnknown() {
        Assert.areEqual(SupportConstants.SENT_POSITIVE, eval('Thanks', 'Great product, I love it, very helpful.').sentiment);
        Assert.areEqual(SupportConstants.SENT_NEUTRAL, eval('Question', 'How do I export a report?').sentiment);
        Assert.areEqual(SupportConstants.SENT_UNKNOWN, eval(null, null).sentiment);
        Assert.areEqual(SupportConstants.SENT_UNKNOWN, eval('   ', '').sentiment);
    }

    @IsTest
    static void generalCaseDefaultsToLowPriority() {
        CaseRoutingRules.Decision d = eval('Question', 'Do you have a partner program?');
        Assert.areEqual(SupportConstants.CAT_GENERAL, d.category);
        Assert.areEqual(SupportConstants.PRIORITY_LOW, d.recommendedPriority);
        Assert.areEqual(SupportConstants.ROUTE_GENERAL, d.routeKey);
    }

    @IsTest
    static void shippingAndProductDefectCategories() {
        Assert.areEqual(SupportConstants.CAT_SHIPPING, eval('Where is my parcel', 'The tracking number shows no movement.').category);
        Assert.areEqual(SupportConstants.CAT_PRODUCT, eval('Faulty unit', 'The device is defective and overheats.').category);
        Assert.areEqual(SupportConstants.CAT_TECHNICAL, eval('App crash', 'The mobile app crashes on start.').category);
    }

    @IsTest
    static void matchingIsWholeWordSoDischargeIsNotACharge() {
        Assert.areEqual(SupportConstants.CAT_GENERAL, eval('Battery discharge', 'It happens overnight.').category);
    }

    @IsTest
    static void nullInputYieldsSafeDefault() {
        CaseRoutingRules.Decision d = CaseRoutingRules.evaluate(null);
        Assert.areEqual(SupportConstants.CAT_GENERAL, d.category);
        Assert.areEqual(SupportConstants.SENT_UNKNOWN, d.sentiment);
        Assert.isFalse(d.mustEscalate());
        Assert.isNotNull(d.explanation);
        Assert.isFalse(d.troubleshootingSteps.isEmpty());
    }

    @IsTest
    static void veryLongTextIsHandledWithoutError() {
        String longText = 'lorem '.repeat(5000) + ' refund';
        CaseRoutingRules.Decision d = eval('Long text', longText);
        Assert.isNotNull(d.category, 'Text beyond the limit is ignored but never causes an exception.');
    }

    @IsTest
    static void knownLimitationNegationIsNotUnderstood() {
        // Documented limitation (docs/security-review.md): keyword rules cannot understand negation.
        CaseRoutingRules.Decision d = eval('Question', 'This is not an outage, just a question about outage notices.');
        Assert.isTrue(d.outageSuspected, 'Rules are intentionally conservative: they escalate rather than miss an outage.');
    }

    @IsTest
    static void everyCategoryHasTroubleshootingStepsAndAnExplanation() {
        List<CaseRoutingRules.Decision> decisions = new List<CaseRoutingRules.Decision>{
            eval('Invoice', 'billing'), eval('Cannot log in', 'password'), eval('Data breach', 'x'), eval('Parcel', 'shipping'),
            eval('Defective', 'broken'), eval('Crash', 'error'), eval('Hello', 'Anything')
        };
        for (CaseRoutingRules.Decision d : decisions) {
            Assert.isFalse(d.troubleshootingSteps.isEmpty(), 'Missing troubleshooting for ' + d.category);
            Assert.isTrue(d.explanation.contains(d.category));
        }
    }

    @IsTest
    static void priorityHelpers() {
        Assert.areEqual(3, CaseRoutingRules.priorityRank(SupportConstants.PRIORITY_HIGH));
        Assert.areEqual(2, CaseRoutingRules.priorityRank(SupportConstants.PRIORITY_MEDIUM));
        Assert.areEqual(1, CaseRoutingRules.priorityRank(SupportConstants.PRIORITY_LOW));
        Assert.areEqual(0, CaseRoutingRules.priorityRank(null));
        Assert.areEqual(SupportConstants.PRIORITY_HIGH, CaseRoutingRules.higherPriority(SupportConstants.PRIORITY_LOW, SupportConstants.PRIORITY_HIGH));
        Assert.areEqual(SupportConstants.PRIORITY_MEDIUM, CaseRoutingRules.higherPriority(SupportConstants.PRIORITY_MEDIUM, SupportConstants.PRIORITY_LOW));
    }

    @IsTest
    static void routeKeyForCategoryCoversEveryCategory() {
        Assert.areEqual(SupportConstants.ROUTE_BILLING, CaseRoutingRules.routeKeyForCategory(SupportConstants.CAT_BILLING));
        Assert.areEqual(SupportConstants.ROUTE_TECHNICAL, CaseRoutingRules.routeKeyForCategory(SupportConstants.CAT_TECHNICAL));
        Assert.areEqual(SupportConstants.ROUTE_ACCESS, CaseRoutingRules.routeKeyForCategory(SupportConstants.CAT_ACCESS));
        Assert.areEqual(SupportConstants.ROUTE_SECURITY, CaseRoutingRules.routeKeyForCategory(SupportConstants.CAT_SECURITY));
        Assert.areEqual(SupportConstants.ROUTE_SHIPPING, CaseRoutingRules.routeKeyForCategory(SupportConstants.CAT_SHIPPING));
        Assert.areEqual(SupportConstants.ROUTE_PRODUCT, CaseRoutingRules.routeKeyForCategory(SupportConstants.CAT_PRODUCT));
        Assert.areEqual(SupportConstants.ROUTE_GENERAL, CaseRoutingRules.routeKeyForCategory('something else'));
        Assert.areEqual(SupportConstants.ROUTE_GENERAL, CaseRoutingRules.routeKeyForCategory(null));
    }
}
