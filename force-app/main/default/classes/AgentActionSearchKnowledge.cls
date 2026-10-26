/** Agent / Flow action: search approved Knowledge articles and return a grounded answer or INSUFFICIENT_EVIDENCE. */
public with sharing class AgentActionSearchKnowledge {

    public class Request {
        @InvocableVariable(label='Customer Question' description='The customer question to look up in approved Knowledge articles (max 500 characters).' required=true)
        public String question;
        @InvocableVariable(label='Case Id' description='Optional. The related case; an unsuccessful search counts as a failed attempt on this case.')
        public String caseId;
    }

    public class Response {
        @InvocableVariable(label='Status' description='FOUND, INSUFFICIENT_EVIDENCE, UNAVAILABLE or INVALID_INPUT')
        public String status;
        @InvocableVariable(label='Answer' description='Answer assembled only from retrieved article content. Empty when no reliable evidence exists.')
        public String answer;
        @InvocableVariable(label='Source Articles' description='Titles and URL names of the articles used as evidence.')
        public String sources;
        @InvocableVariable(label='Human Recommended' description='True when the agent should offer human assistance.')
        public Boolean humanRecommended;
        @InvocableVariable(label='Message' description='Plain-language message that can be shown to the customer.')
        public String message;
    }

    @InvocableMethod(label='SmartSupport: Search Knowledge' description='Searches approved, published Knowledge articles the running user may read and returns a grounded answer, or INSUFFICIENT_EVIDENCE when nothing reliable is found.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            Response res = new Response();
            KnowledgeSearchService.SearchResult result = AgentforceActionService.searchKnowledge(req == null ? null : req.question, req == null ? null : req.caseId);
            res.status = result.status;
            res.answer = result.answer;
            res.humanRecommended = result.humanRecommended;
            res.message = result.message;
            List<String> sourceLines = new List<String>();
            for (KnowledgeSearchService.Article a : result.articles) {
                sourceLines.add(a.title + (String.isBlank(a.urlName) ? '' : ' (' + a.urlName + ')'));
            }
            res.sources = String.join(sourceLines, '; ');
            responses.add(res);
        }
        return responses;
    }
}
