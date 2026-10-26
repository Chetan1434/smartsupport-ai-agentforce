/**
 * The deterministic rules engine of SmartSupport AI.
 *
 * Pure logic: no SOQL, no DML, no callouts. Given the text of a case it returns a Decision (category, sentiment,
 * recommended priority, escalation reason, routing key, suggested action). Because it is side-effect free it is
 * easy to unit test, and it is the ONLY place where classification rules live (triggers, Flows, LWC and Agentforce
 * actions all call it indirectly through CaseIntelligenceService).
 *
 * Matching is whole-word / whole-phrase on normalized text (lower case, punctuation removed). A term that ends
 * with '*' is a prefix match (for example 'invoice*' matches invoice, invoices, invoiced).
 *
 * LIMITATIONS (documented in docs/security-review.md): keyword rules are English-only and do not understand
 * negation ("this is NOT an outage"). They produce RECOMMENDATIONS plus a small set of deterministic escalations.
 */
public with sharing class CaseRoutingRules {
    @TestVisible private static final Integer MAX_TEXT_LENGTH = 10000;

    // ---- Rule vocabularies (normalized form: lower case, no punctuation) ----
    @TestVisible private static final List<String> SECURITY_TERMS = new List<String>{
        'data breach', 'security breach', 'data leak', 'leaked', 'unauthorized access', 'unauthorised access',
        'unauthorized login', 'unauthorised login', 'hacked', 'account compromised', 'compromised account',
        'account takeover', 'someone else logged in', 'did not log in', 'ransomware', 'phishing',
        'stolen credentials', 'suspicious activity'
    };
    @TestVisible private static final List<String> OUTAGE_TERMS = new List<String>{
        'outage*', 'service is down', 'system is down', 'site is down', 'platform is down', 'application is down',
        'down for everyone', 'down for all', 'all users', 'all of our users', 'all customers', 'everyone is affected',
        'entire team', 'widespread', 'production is down', 'production down', 'completely down', 'nobody can',
        'no one can', 'cannot access anything'
    };
    @TestVisible private static final List<String> ACCESS_TERMS = new List<String>{
        'password*', 'log in', 'login*', 'logging in', 'logged out', 'sign in', 'signin', 'locked out',
        'account locked', 'account is locked', '2fa', 'mfa', 'two factor', 'verification code', 'single sign on', 'sso',
        'cannot access my account', 'unable to access my account'
    };
    @TestVisible private static final List<String> BILLING_TERMS = new List<String>{
        'invoice*', 'billing', 'billed', 'charge', 'charged', 'charges', 'double charge', 'overcharg*', 'refund*',
        'payment*', 'subscription*', 'credit card', 'receipt*', 'pricing', 'price', 'renewal*', 'dispute*'
    };
    @TestVisible private static final List<String> SHIPPING_TERMS = new List<String>{
        'shipping', 'shipment*', 'shipped', 'delivery', 'tracking number', 'tracking', 'package*',
        'parcel*', 'courier', 'not received', 'never arrived', 'lost in transit', 'damaged in transit'
    };
    @TestVisible private static final List<String> PRODUCT_TERMS = new List<String>{
        'defective', 'defect*', 'faulty', 'malfunction*', 'broken', 'cracked', 'overheat*', 'damaged', 'replacement*',
        'does not turn on', 'will not turn on', 'wont turn on'
    };
    @TestVisible private static final List<String> TECHNICAL_TERMS = new List<String>{
        'error*', 'bug*', 'crash*', 'exception*', 'timeout*', 'timed out', 'slow', 'not loading', 'not working',
        'stopped working', 'integration*', 'api', 'sync', 'failing', 'failed', 'freezes', 'freezing', 'unresponsive'
    };
    @TestVisible private static final List<String> HUMAN_TERMS = new List<String>{
        'a human', 'real human', 'human agent', 'human support', 'human being', 'real person', 'live agent',
        'live person', 'real agent', 'speak to an agent', 'talk to an agent', 'speak to a person', 'talk to a person',
        'speak with a person', 'speak to someone', 'talk to someone', 'speak with someone', 'talk with someone',
        'a representative'
    };
    @TestVisible private static final List<String> NEGATIVE_TERMS = new List<String>{
        'angry', 'furious', 'unacceptable', 'terrible', 'horrible', 'worst', 'awful', 'frustrated', 'frustrating',
        'disappointed', 'ridiculous', 'useless', 'cancel*', 'lawsuit', 'fed up', 'still waiting', 'third time',
        'second time', 'not happy', 'unhappy', 'outraged', 'disgusted', 'complaint*', 'never again'
    };
    @TestVisible private static final List<String> POSITIVE_TERMS = new List<String>{
        'thanks', 'thank you', 'appreciate*', 'great', 'love', 'excellent', 'happy with', 'helpful', 'wonderful',
        'pleased'
    };

    /** Input to the rules engine. */
    public class Input {
        public String subject;
        public String description;
        public Integer failedAttempts = 0;
        public Integer failedAttemptThreshold = 2;
        public Boolean premiumAccount = false;
    }

    /** Output of the rules engine. */
    public class Decision {
        public String category = SupportConstants.CAT_GENERAL;
        public String sentiment = SupportConstants.SENT_UNKNOWN;
        public String recommendedPriority = SupportConstants.PRIORITY_LOW;
        public Boolean securityConcern = false;
        public Boolean outageSuspected = false;
        public Boolean humanRequested = false;
        public Boolean repeatedFailure = false;
        public Boolean premiumEscalation = false;
        /** One of SupportConstants.REASON_* or null when no escalation is required. */
        public String escalationReason;
        /** Routing key (Queue_Mapping__mdt) of the category queue. */
        public String routeKey = SupportConstants.ROUTE_GENERAL;
        /** Routing key used when the case is escalated (may equal routeKey). */
        public String escalationRouteKey = SupportConstants.ROUTE_GENERAL;
        public String suggestedAction;
        public List<String> troubleshootingSteps = new List<String>();
        public List<String> signals = new List<String>();
        public String explanation;

        public Boolean mustEscalate() {
            return escalationReason != null;
        }
        /** True for deterministic urgent signals that are allowed to change the standard Priority field. */
        public Boolean isUrgentByRule() {
            return securityConcern || outageSuspected;
        }
    }

    /** Evaluates the rules for one case. Never throws; a null input yields a safe General/Unknown decision. */
    public static Decision evaluate(Input input) {
        Decision d = new Decision();
        if (input == null) {
            d.explanation = 'No case text was supplied, so the default General category was used.';
            d.suggestedAction = suggestedActionFor(d);
            d.troubleshootingSteps = troubleshootingFor(d.category);
            return d;
        }

        String padded = normalize(joinText(input.subject, input.description));
        Boolean hasText = padded.length() > 2;

        List<String> securityHits = matches(padded, SECURITY_TERMS);
        List<String> outageHits = matches(padded, OUTAGE_TERMS);
        List<String> accessHits = matches(padded, ACCESS_TERMS);
        List<String> billingHits = matches(padded, BILLING_TERMS);
        List<String> shippingHits = matches(padded, SHIPPING_TERMS);
        List<String> productHits = matches(padded, PRODUCT_TERMS);
        List<String> technicalHits = matches(padded, TECHNICAL_TERMS);
        List<String> humanHits = matches(padded, HUMAN_TERMS);

        d.securityConcern = !securityHits.isEmpty();
        d.outageSuspected = !outageHits.isEmpty();
        d.humanRequested = !humanHits.isEmpty();
        Integer threshold = (input.failedAttemptThreshold == null || input.failedAttemptThreshold < 1) ? 2 : input.failedAttemptThreshold;
        d.repeatedFailure = input.failedAttempts != null && input.failedAttempts >= threshold;

        // ---- Category precedence: Security > outage (Technical) > Account Access > Billing > Shipping > Product > Technical > General
        if (d.securityConcern) {
            d.category = SupportConstants.CAT_SECURITY;
            d.routeKey = SupportConstants.ROUTE_SECURITY;
            addSignals(d, 'security', securityHits);
        } else if (d.outageSuspected) {
            d.category = SupportConstants.CAT_TECHNICAL;
            d.routeKey = SupportConstants.ROUTE_TECHNICAL;
            addSignals(d, 'outage', outageHits);
        } else if (!accessHits.isEmpty()) {
            d.category = SupportConstants.CAT_ACCESS;
            d.routeKey = SupportConstants.ROUTE_ACCESS;
            addSignals(d, 'account access', accessHits);
        } else if (!billingHits.isEmpty()) {
            d.category = SupportConstants.CAT_BILLING;
            d.routeKey = SupportConstants.ROUTE_BILLING;
            addSignals(d, 'billing', billingHits);
        } else if (!shippingHits.isEmpty()) {
            d.category = SupportConstants.CAT_SHIPPING;
            d.routeKey = SupportConstants.ROUTE_SHIPPING;
            addSignals(d, 'shipping', shippingHits);
        } else if (!productHits.isEmpty()) {
            d.category = SupportConstants.CAT_PRODUCT;
            d.routeKey = SupportConstants.ROUTE_PRODUCT;
            addSignals(d, 'product defect', productHits);
        } else if (!technicalHits.isEmpty()) {
            d.category = SupportConstants.CAT_TECHNICAL;
            d.routeKey = SupportConstants.ROUTE_TECHNICAL;
            addSignals(d, 'technical', technicalHits);
        } else {
            d.category = SupportConstants.CAT_GENERAL;
            d.routeKey = SupportConstants.ROUTE_GENERAL;
        }
        if (d.humanRequested) {
            addSignals(d, 'human request', humanHits);
        }

        d.sentiment = detectSentiment(padded, hasText);
        d.recommendedPriority = recommendPriority(d);

        // ---- Escalation reason precedence: Security > Outage > Customer asked for a human > Repeated failure > Premium + High
        d.premiumEscalation = input.premiumAccount == true && d.recommendedPriority == SupportConstants.PRIORITY_HIGH;
        if (d.securityConcern) {
            d.escalationReason = SupportConstants.REASON_SECURITY;
            d.escalationRouteKey = SupportConstants.ROUTE_SECURITY;
        } else if (d.outageSuspected) {
            d.escalationReason = SupportConstants.REASON_OUTAGE;
            d.escalationRouteKey = SupportConstants.ROUTE_URGENT;
        } else if (d.humanRequested) {
            d.escalationReason = SupportConstants.REASON_HUMAN;
            d.escalationRouteKey = d.routeKey;
        } else if (d.repeatedFailure) {
            d.escalationReason = SupportConstants.REASON_AI_FAILURE;
            d.escalationRouteKey = d.routeKey;
        } else if (d.premiumEscalation) {
            d.escalationReason = SupportConstants.REASON_PREMIUM;
            d.escalationRouteKey = SupportConstants.ROUTE_URGENT;
        } else {
            d.escalationRouteKey = d.routeKey;
        }

        d.suggestedAction = suggestedActionFor(d);
        d.troubleshootingSteps = troubleshootingFor(d.category);
        d.explanation = buildExplanation(d);
        return d;
    }

    /** Maps an Issue_Category__c value to its Queue_Mapping__mdt routing key. Unknown categories route to General. */
    public static String routeKeyForCategory(String category) {
        if (category == SupportConstants.CAT_BILLING) {
            return SupportConstants.ROUTE_BILLING;
        }
        if (category == SupportConstants.CAT_TECHNICAL) {
            return SupportConstants.ROUTE_TECHNICAL;
        }
        if (category == SupportConstants.CAT_ACCESS) {
            return SupportConstants.ROUTE_ACCESS;
        }
        if (category == SupportConstants.CAT_SECURITY) {
            return SupportConstants.ROUTE_SECURITY;
        }
        if (category == SupportConstants.CAT_SHIPPING) {
            return SupportConstants.ROUTE_SHIPPING;
        }
        if (category == SupportConstants.CAT_PRODUCT) {
            return SupportConstants.ROUTE_PRODUCT;
        }
        return SupportConstants.ROUTE_GENERAL;
    }

    /** Returns the higher of two priorities (High > Medium > Low). Unknown values rank below Low. */
    public static String higherPriority(String a, String b) {
        return priorityRank(a) >= priorityRank(b) ? a : b;
    }

    public static Integer priorityRank(String priority) {
        if (priority == SupportConstants.PRIORITY_HIGH) {
            return 3;
        }
        if (priority == SupportConstants.PRIORITY_MEDIUM) {
            return 2;
        }
        if (priority == SupportConstants.PRIORITY_LOW) {
            return 1;
        }
        return 0;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------
    private static String joinText(String subject, String description) {
        return (subject == null ? '' : subject) + ' ' + (description == null ? '' : description);
    }

    /** Lower-cases, strips apostrophes, replaces every other non-alphanumeric run with one space, pads with spaces. */
    @TestVisible
    private static String normalize(String raw) {
        if (String.isBlank(raw)) {
            return ' ';
        }
        String s = raw.length() > MAX_TEXT_LENGTH ? raw.substring(0, MAX_TEXT_LENGTH) : raw;
        s = s.toLowerCase();
        s = s.replaceAll('[\'’‘`]', '');
        s = s.replaceAll('[^a-z0-9]+', ' ');
        return ' ' + s.trim() + ' ';
    }

    private static List<String> matches(String padded, List<String> terms) {
        List<String> hits = new List<String>();
        for (String term : terms) {
            if (termPresent(padded, term)) {
                hits.add(term.endsWith('*') ? term.substring(0, term.length() - 1) : term);
            }
        }
        return hits;
    }

    private static Boolean termPresent(String padded, String term) {
        if (term.endsWith('*')) {
            return padded.contains(' ' + term.substring(0, term.length() - 1));
        }
        return padded.contains(' ' + term + ' ');
    }

    private static void addSignals(Decision d, String label, List<String> hits) {
        Integer count = 0;
        for (String hit : hits) {
            if (count >= 3) {
                break;
            }
            d.signals.add(label + ': ' + hit);
            count++;
        }
    }

    private static String detectSentiment(String padded, Boolean hasText) {
        if (!hasText) {
            return SupportConstants.SENT_UNKNOWN;
        }
        Integer negative = matches(padded, NEGATIVE_TERMS).size();
        Integer positive = matches(padded, POSITIVE_TERMS).size();
        if (negative > positive) {
            return SupportConstants.SENT_NEGATIVE;
        }
        if (positive > negative) {
            return SupportConstants.SENT_POSITIVE;
        }
        return SupportConstants.SENT_NEUTRAL;
    }

    private static String recommendPriority(Decision d) {
        String priority;
        if (d.securityConcern || d.outageSuspected) {
            priority = SupportConstants.PRIORITY_HIGH;
        } else if (d.category == SupportConstants.CAT_GENERAL) {
            priority = SupportConstants.PRIORITY_LOW;
        } else {
            priority = SupportConstants.PRIORITY_MEDIUM;
        }
        // Negative sentiment raises a recommendation by one level (never above High).
        if (d.sentiment == SupportConstants.SENT_NEGATIVE) {
            if (priority == SupportConstants.PRIORITY_LOW) {
                priority = SupportConstants.PRIORITY_MEDIUM;
            } else if (priority == SupportConstants.PRIORITY_MEDIUM) {
                priority = SupportConstants.PRIORITY_HIGH;
            }
        }
        return priority;
    }

    private static String suggestedActionFor(Decision d) {
        if (d.securityConcern) {
            return 'Treat as a security incident: engage the Security Response team now and verify the customer through a trusted channel. Never ask for passwords.';
        }
        if (d.outageSuspected) {
            return 'Possible widespread outage: check open incidents, link this case to the incident and notify the on-call team.';
        }
        if (d.humanRequested) {
            return 'Customer asked for a human: contact the customer personally and do not send automated replies.';
        }
        if (d.repeatedFailure) {
            return 'Automated help failed repeatedly: review the history and contact the customer personally.';
        }
        if (d.premiumEscalation) {
            return 'Premium account with a high-priority case: handle with priority according to your premium support policy.';
        }
        if (d.category == SupportConstants.CAT_BILLING) {
            return 'Identify the invoice or charge in question and route to the billing team. Do not promise refunds.';
        }
        if (d.category == SupportConstants.CAT_ACCESS) {
            return 'Confirm the username and whether a reset email was received; follow the account recovery article in Knowledge.';
        }
        if (d.category == SupportConstants.CAT_SHIPPING) {
            return 'Confirm the order number and check the carrier tracking status.';
        }
        if (d.category == SupportConstants.CAT_PRODUCT) {
            return 'Collect model, serial number and photos, then route to product support for evaluation.';
        }
        if (d.category == SupportConstants.CAT_TECHNICAL) {
            return 'Collect exact error messages, time and affected users; search Knowledge for a known issue.';
        }
        return 'Ask clarifying questions and search Knowledge for a matching article.';
    }

    private static List<String> troubleshootingFor(String category) {
        if (category == SupportConstants.CAT_SECURITY) {
            return new List<String>{
                'Do not request passwords or secrets in the case.',
                'Hand the case to the Security Response team immediately.',
                'Preserve the details the customer reported (time, account, what they observed).'
            };
        }
        if (category == SupportConstants.CAT_ACCESS) {
            return new List<String>{
                'Confirm the affected username and when the problem started.',
                'Ask whether a password reset email arrived (check spam).',
                'Check whether the account is locked or uses multi-factor authentication.',
                'If identity cannot be verified, hand the case to a human agent.'
            };
        }
        if (category == SupportConstants.CAT_BILLING) {
            return new List<String>{
                'Identify the invoice or charge (number, date, amount).',
                'Compare it with the active subscription record.',
                'Do not promise refunds or credits; follow the billing policy.',
                'Route to a billing specialist when an adjustment is requested.'
            };
        }
        if (category == SupportConstants.CAT_SHIPPING) {
            return new List<String>{
                'Confirm the order number and shipping address.',
                'Check the carrier tracking status.',
                'If the parcel is late or lost, hand over to the shipping team.'
            };
        }
        if (category == SupportConstants.CAT_PRODUCT) {
            return new List<String>{
                'Collect the model, serial number and photos of the problem.',
                'Search Knowledge for a known issue for this product.',
                'Route to product support for evaluation; do not promise a replacement.'
            };
        }
        if (category == SupportConstants.CAT_TECHNICAL) {
            return new List<String>{
                'Capture exact error messages, timestamps and affected users.',
                'Check whether other customers report the same problem (possible incident).',
                'Record browser or app version and reproduction steps.',
                'Escalate to engineering when the problem is reproducible.'
            };
        }
        return new List<String>{
            'Ask clarifying questions to understand the request.',
            'Search Knowledge for matching articles.'
        };
    }

    private static String buildExplanation(Decision d) {
        String signalText = d.signals.isEmpty() ? 'no strong keyword signals' : String.join(d.signals, '; ');
        String escalation = d.mustEscalate() ? ('Escalation required: ' + d.escalationReason + '.') : 'No escalation rule matched.';
        return 'Category "' + d.category + '" from ' + signalText + '. Sentiment: ' + d.sentiment
            + '. Recommended priority: ' + d.recommendedPriority + '. ' + escalation;
    }
}
