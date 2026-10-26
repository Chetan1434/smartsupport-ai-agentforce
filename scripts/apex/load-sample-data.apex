// Optional alternative to the CSV import: creates fictional accounts, contacts and cases WITH relationships.
// Run:  sf apex run --file scripts/apex/load-sample-data.apex --target-org <alias>
// The Case trigger classifies each case on insert, so the results are visible immediately.
List<Account> accounts = new List<Account>{
    new Account(Name = 'Northwind Demo Traders', Support_Tier__c = 'Premium'),
    new Account(Name = 'Contoso Sample Logistics', Support_Tier__c = 'Standard'),
    new Account(Name = 'Fabrikam Example Health', Support_Tier__c = 'Premium'),
    new Account(Name = 'Tailspin Demo Outfitters', Support_Tier__c = 'Standard'),
    new Account(Name = 'Adventure Sample Works', Support_Tier__c = 'Standard')
};
insert accounts;
List<Contact> contacts = new List<Contact>();
String[][] people = new String[][]{
    new String[]{'Avery', 'Quill'}, new String[]{'Blake', 'Hartwell'}, new String[]{'Casey', 'Moreno'},
    new String[]{'Devon', 'Park'}, new String[]{'Emery', 'Stone'}
};
for (Integer i = 0; i < people.size(); i++) {
    contacts.add(new Contact(FirstName = people[i][0], LastName = people[i][1], AccountId = accounts[i].Id,
        Email = (people[i][0] + '.' + people[i][1]).toLowerCase() + '@example.invalid'));
}
insert contacts;
String[][] cases = new String[][]{
    new String[]{'Password reset link never arrives', 'I requested a password reset three times and no e-mail arrives.', '0'},
    new String[]{'Cannot log in after changing phone', 'Login fails with an invalid verification code. I cannot sign in.', '3'},
    new String[]{'Charged twice on the March invoice', 'Duplicate charge on my invoice. I want a refund. This is unacceptable.', '2'},
    new String[]{'Scanner arrives with a cracked screen', 'The device arrived defective with a cracked screen.', '1'},
    new String[]{'Service is down for all users', 'Widespread outage. Nobody can work.', '0'},
    new String[]{'Suspicious logins - unauthorized access', 'We found unauthorized access and fear a data breach.', '0'},
    new String[]{'Please connect me with a person', 'I want to speak to a human agent.', '4'},
    new String[]{'General question about the partner program', 'Do you offer a partner program?', '3'}
};
List<Case> toInsert = new List<Case>();
for (String[] row : cases) {
    Integer idx = Integer.valueOf(row[2]);
    toInsert.add(new Case(Subject = row[0], Description = row[1], Origin = 'Web', AccountId = accounts[idx].Id, ContactId = contacts[idx].Id));
}
insert toInsert;
System.debug('Created ' + accounts.size() + ' accounts, ' + contacts.size() + ' contacts, ' + toInsert.size() + ' cases.');
