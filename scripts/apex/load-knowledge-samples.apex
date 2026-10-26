// Creates and publishes the 5 fictional sample Knowledge articles (see data/knowledge-samples/).
// Requires: Lightning Knowledge enabled, and your user has the "Knowledge User" box ticked.
// Run: sf apex run --file scripts/apex/load-knowledge-samples.apex --target-org <alias>
// Idempotent for drafts: existing DRAFT versions with the same URL names are deleted and recreated.
Map<String, String[]> articles = new Map<String, String[]>{
    'reset-your-password' => new String[]{
        'How to reset your password',
        'Open the sign-in page and select "Forgot your password". Enter the e-mail address of your account. A reset link is sent within a few minutes and stays valid for 24 hours. Check your spam folder. If no e-mail arrives after 15 minutes, contact support so an administrator can verify your identity and resend the link.'},
    'unlock-account-failed-logins' => new String[]{
        'Unlock your account after failed login attempts',
        'An account locks after five failed login attempts. The lock clears automatically after 15 minutes. An administrator can unlock it sooner. If you changed phones and the verification code fails, contact support to re-register your authenticator. Support never asks for your password.'},
    'invoice-and-billing-disputes' => new String[]{
        'Understanding your invoice and disputing a charge',
        'Each invoice lists the plan, usage and taxes for the billing period. If you see a duplicate or unexpected charge, open a case with the invoice number and the amount in question. The billing team reviews disputes and replies with the outcome. Refund decisions are made by the billing team, not by the automated assistant.'},
    'report-defective-product' => new String[]{
        'Report a defective or damaged product',
        'Open a case with the serial number, a short description and photos of the damage. Do not attempt repairs. The product team will confirm whether a replacement or repair applies. Firmware problems: restart the device and confirm the firmware version in Settings before contacting support.'},
    'service-outage-guidance' => new String[]{
        'What to do during a service outage',
        'During a widespread outage the support team posts updates and handles cases with urgent priority. Open one case per organisation and include the time the problem started and the affected users. Suspected security incidents are handled separately and immediately by the security response team.'}
};

delete [SELECT Id FROM Knowledge__kav WHERE PublishStatus = 'Draft' AND UrlName IN :articles.keySet()];

List<Knowledge__kav> drafts = new List<Knowledge__kav>();
for (String urlName : articles.keySet()) {
    drafts.add(new Knowledge__kav(Title = articles.get(urlName)[0], UrlName = urlName, Summary = articles.get(urlName)[1]));
}
insert drafts;

Integer published = 0;
for (Knowledge__kav draft : [SELECT KnowledgeArticleId, Title FROM Knowledge__kav WHERE Id IN :drafts]) {
    try {
        KbManagement.PublishingService.publishArticle(draft.KnowledgeArticleId, true);
        published++;
    } catch (Exception e) {
        System.debug('PUBLISH FAILED for ' + draft.Title + ': ' + e.getMessage());
    }
}
System.debug('KNOWLEDGE: created ' + drafts.size() + ', published ' + published);
