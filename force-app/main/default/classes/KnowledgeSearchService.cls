/**
 * Retrieval step of the RAG pattern: finds PUBLISHED Knowledge articles the running user may read and decides
 * whether they are reliable evidence for the question.
 *
 * Design points
 *  - Dynamic SOSL (Search.query ... AccessLevel.USER_MODE) so the project still compiles and deploys in orgs where
 *    Lightning Knowledge (Knowledge__kav) is not enabled; the service then answers UNAVAILABLE.
 *  - The SOSL search string is built ONLY from tokens matching [a-z0-9]+, so user text can never inject SOSL.
 *  - Evidence rule: an article counts only if it contains enough of the question terms (title + summary).
 *    No evidence -> INSUFFICIENT_EVIDENCE and a human is recommended. An answer is NEVER invented.
 *  - Article text is untrusted data: it is length-limited and articles containing instruction-like text
 *    (possible prompt injection) are excluded from the evidence.
 */
public with sharing class KnowledgeSearchService {
    private static final String KNOWLEDGE_OBJECT = 'Knowledge__kav';
    private static final Integer MAX_TERMS = 8;
    private static final Integer MAX_SUMMARY_LENGTH = 500;

    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'and', 'for', 'are', 'but', 'not', 'you', 'your', 'with', 'have', 'has', 'had', 'was', 'were', 'this',
        'that', 'from', 'they', 'will', 'would', 'could', 'should', 'can', 'cant', 'cannot', 'how', 'what', 'when',
        'where', 'why', 'who', 'which', 'does', 'did', 'doing', 'dont', 'any', 'all', 'our', 'out', 'about', 'into',
        'than', 'then', 'them', 'there', 'their', 'its', 'been', 'being', 'just', 'also', 'get', 'got', 'need',
        'want', 'please', 'help', 'hello', 'hi', 'thanks', 'thank', 'me', 'my', 'is', 'it', 'to', 'do', 'of', 'in',
        'on', 'at', 'be', 'an', 'as', 'by', 'or', 'if', 'so', 'we', 'us', 'am'
    };

    private static final List<String> INJECTION_MARKERS = new List<String>{
        'ignore previous instructions', 'ignore all previous', 'ignore the above', 'disregard previous',
        'disregard all previous', 'you are now', 'system prompt', 'reveal your instructions', 'act as an',
        'new instructions:'
    };

    /** Test hook: when set, these candidates are used instead of a SOSL search. */
    @TestVisible private static List<Article> candidateOverride;

    public class Article {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String urlName;
        @AuraEnabled public Integer matchedTerms = 0;

        public Article() {
        }

        public Article(String id, String title, String summary, String urlName) {
            this.id = id;
            this.title = title;
            this.summary = summary;
            this.urlName = urlName;
        }
    }

    public class SearchResult {
        /** One of SupportConstants.KB_FOUND / KB_INSUFFICIENT / KB_UNAVAILABLE / KB_INVALID. */
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        /** Grounded answer text assembled only from retrieved article content, or null. */
        @AuraEnabled public String answer;
        @AuraEnabled public Boolean humanRecommended = false;
        @AuraEnabled public List<Article> articles = new List<Article>();
    }

    /** Searches Knowledge for the question. Never throws. */
    public static SearchResult search(String question) {
        SearchResult result = new SearchResult();
        if (String.isBlank(question)) {
            return invalid(result, 'Please type a question.');
        }
        if (question.length() > SupportConstants.MAX_QUESTION_LENGTH) {
            return invalid(result, 'Please shorten the question to ' + SupportConstants.MAX_QUESTION_LENGTH + ' characters or fewer.');
        }
        List<String> terms = extractTerms(question);
        if (terms.isEmpty()) {
            return invalid(result, 'Please add a little more detail to the question.');
        }

        List<Article> candidates;
        if (candidateOverride != null) {
            candidates = candidateOverride;
        } else {
            if (!Schema.getGlobalDescribe().containsKey(KNOWLEDGE_OBJECT.toLowerCase())) {
                result.status = SupportConstants.KB_UNAVAILABLE;
                result.message = 'Salesforce Knowledge is not enabled in this org, so no articles can be searched.';
                result.humanRecommended = true;
                return result;
            }
            try {
                candidates = fetchCandidates(terms);
            } catch (Exception e) {
                result.status = SupportConstants.KB_UNAVAILABLE;
                result.message = 'Knowledge search is currently unavailable or you do not have access to Knowledge.';
                result.humanRecommended = true;
                return result;
            }
        }

        List<Article> evidence = rank(candidates, terms, SupportConstants.knowledgeMinMatchedTerms(), SupportConstants.knowledgeMaxResults());
        if (evidence.isEmpty()) {
            result.status = SupportConstants.KB_INSUFFICIENT;
            result.message = 'I could not find a reliable answer in the approved Knowledge articles. A human agent can help with this.';
            result.humanRecommended = true;
            return result;
        }
        result.status = SupportConstants.KB_FOUND;
        result.articles = evidence;
        result.answer = buildAnswer(evidence[0]);
        result.message = 'Found ' + evidence.size() + ' relevant article(s).';
        return result;
    }

    /** Splits a question into lower-case alphanumeric terms, removes stop words and duplicates, light plural stemming. */
    @TestVisible
    private static List<String> extractTerms(String question) {
        List<String> terms = new List<String>();
        Set<String> seen = new Set<String>();
        String cleaned = question.toLowerCase().replaceAll('[\'’]', '').replaceAll('[^a-z0-9]+', ' ').trim();
        for (String token : cleaned.split(' ')) {
            if (token.length() < 3 || STOP_WORDS.contains(token)) {
                continue;
            }
            String term = (token.length() > 4 && token.endsWith('s')) ? token.substring(0, token.length() - 1) : token;
            if (seen.add(term)) {
                terms.add(term);
            }
            if (terms.size() >= MAX_TERMS) {
                break;
            }
        }
        return terms;
    }

    private static List<Article> fetchCandidates(List<String> terms) {
        String searchTerm = String.join(terms, ' OR ');
        String sosl = 'FIND \'' + searchTerm + '\' IN ALL FIELDS RETURNING ' + KNOWLEDGE_OBJECT
            + ' (Id, Title, Summary, UrlName WHERE PublishStatus = \'Online\') LIMIT 25';
        List<List<SObject>> found = Search.query(sosl, AccessLevel.USER_MODE);
        List<Article> articles = new List<Article>();
        if (found == null || found.isEmpty()) {
            return articles;
        }
        for (SObject row : found[0]) {
            articles.add(new Article(
                String.valueOf(row.get('Id')),
                (String) row.get('Title'),
                (String) row.get('Summary'),
                (String) row.get('UrlName')
            ));
        }
        return articles;
    }

    /** Scores, filters and sorts candidates. Pure function (no SOQL/DML), unit tested directly. */
    @TestVisible
    private static List<Article> rank(List<Article> candidates, List<String> terms, Integer minMatched, Integer maxResults) {
        List<Article> ranked = new List<Article>();
        if (candidates == null || terms == null || terms.isEmpty()) {
            return ranked;
        }
        Integer required = Math.min(minMatched, terms.size());
        for (Article a : candidates) {
            if (a == null || String.isBlank(a.title) || looksLikeInjection(a)) {
                continue;
            }
            String haystack = ' ' + (a.title + ' ' + (a.summary == null ? '' : a.summary)).toLowerCase().replaceAll('[^a-z0-9]+', ' ') + ' ';
            Integer matched = 0;
            for (String term : terms) {
                if (haystack.contains(' ' + term)) {
                    matched++;
                }
            }
            if (matched >= required) {
                a.matchedTerms = matched;
                if (a.summary != null && a.summary.length() > MAX_SUMMARY_LENGTH) {
                    a.summary = a.summary.substring(0, MAX_SUMMARY_LENGTH);
                }
                ranked.add(a);
            }
        }
        // Selection sort by matchedTerms descending (small lists; avoids a Comparable wrapper class).
        for (Integer i = 0; i < ranked.size(); i++) {
            Integer best = i;
            for (Integer j = i + 1; j < ranked.size(); j++) {
                if (ranked[j].matchedTerms > ranked[best].matchedTerms) {
                    best = j;
                }
            }
            if (best != i) {
                Article tmp = ranked[i];
                ranked[i] = ranked[best];
                ranked[best] = tmp;
            }
        }
        while (ranked.size() > maxResults) {
            ranked.remove(ranked.size() - 1);
        }
        return ranked;
    }

    @TestVisible
    private static Boolean looksLikeInjection(Article a) {
        String text = ((a.title == null ? '' : a.title) + ' ' + (a.summary == null ? '' : a.summary)).toLowerCase();
        for (String marker : INJECTION_MARKERS) {
            if (text.contains(marker)) {
                return true;
            }
        }
        return false;
    }

    private static String buildAnswer(Article top) {
        String body = String.isBlank(top.summary) ? 'Please open the article for the details.' : top.summary;
        return 'According to the Knowledge article "' + top.title + '": ' + body;
    }

    private static SearchResult invalid(SearchResult result, String message) {
        result.status = SupportConstants.KB_INVALID;
        result.message = message;
        return result;
    }
}
