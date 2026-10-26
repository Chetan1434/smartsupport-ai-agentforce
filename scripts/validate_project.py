#!/usr/bin/env python3
"""Offline consistency checks for the SmartSupport AI project (no org needed). Exit code 1 if a check fails.
Checks: XML well-formed; every Apex class has a meta file; custom field/object references in Apex exist;
manifest lists every field/object and nothing missing; picklist constants match field metadata;
LWC @salesforce/apex imports resolve to @AuraEnabled methods; no SeeAllData; no hard-coded 15/18-char record Ids."""
import re, sys, glob, os
import xml.etree.ElementTree as ET
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..')).replace('\\', '/')
D = os.path.join(ROOT, 'force-app/main/default')
problems = []
_glob = glob.glob
def g(pattern, recursive=False):
    """glob with forward-slash paths so the checks also work on Windows."""
    return [x.replace('\\', '/') for x in _glob(pattern, recursive=recursive)]

def bad(m): problems.append(m)
def read(p): return open(p, encoding='utf-8').read()

# 1. XML
for p in g(ROOT + '/**/*.xml', recursive=True):
    if '/node_modules/' in p: continue
    try: ET.parse(p)
    except ET.ParseError as e: bad(f'XML not well-formed: {p}: {e}')

# 2. Apex meta files
apex = g(ROOT + '/force-app/**/*.cls', recursive=True) + g(ROOT + '/optional/**/*.cls', recursive=True)
for p in apex:
    if not os.path.exists(p + '-meta.xml'): bad(f'missing meta file for {p}')

# 3. Fields on disk
fields = {}  # object -> set(field)
for p in g(D + '/objects/*/fields/*.field-meta.xml'):
    obj = p.split('/objects/')[1].split('/')[0]
    fields.setdefault(obj, set()).add(os.path.basename(p).replace('.field-meta.xml', ''))
all_custom = set().union(*fields.values())
std_ok = {'Case__c'}
code = '\n'.join(read(p) for p in apex)
code = re.sub(r'//.*', '', code); code = re.sub(r'/\*.*?\*/', '', code, flags=re.S)
code = re.sub(r"'[^'\n]*'", "''", code)  # ignore string literals
for m in sorted(set(re.findall(r'\b([A-Za-z][A-Za-z0-9_]*__c)\b', code))):
    if m not in all_custom and m not in {'AI_Interaction_Log__c'} and m not in std_ok:
        bad(f'Apex references unknown custom field/object {m}')

# 4. Manifest coverage
man = read(ROOT + '/manifest/package.xml')
ns = {'m': 'http://soap.sforce.com/2006/04/metadata'}
tree = ET.fromstring(man)
listed = {}
for t in tree.findall('m:types', ns):
    listed[t.find('m:name', ns).text] = {x.text for x in t.findall('m:members', ns)}
for obj, fs in fields.items():
    for f in fs:
        if f'{obj}.{f}' not in listed.get('CustomField', set()): bad(f'field {obj}.{f} not in manifest')
for m in listed.get('CustomField', set()):
    o, f = m.split('.')
    if f not in fields.get(o, set()): bad(f'manifest lists missing field {m}')
for name in ('CustomObject', 'CustomTab', 'FlexiPage', 'CustomApplication', 'CustomNotificationType', 'ValidationRule'):
    pass
def exists(kind_dir, suffix, member):
    return os.path.exists(os.path.join(D, kind_dir, member + suffix))
for m in listed.get('CustomObject', set()):
    if not os.path.exists(f'{D}/objects/{m}/{m}.object-meta.xml'): bad(f'manifest CustomObject missing: {m}')
for m in listed.get('CustomTab', set()):
    if not exists('tabs', '.tab-meta.xml', m): bad(f'manifest CustomTab missing: {m}')
for m in listed.get('FlexiPage', set()):
    if not exists('flexipages', '.flexipage-meta.xml', m): bad(f'manifest FlexiPage missing: {m}')
for m in listed.get('CustomApplication', set()):
    if not exists('applications', '.app-meta.xml', m): bad(f'manifest app missing: {m}')
for m in listed.get('CustomNotificationType', set()):
    if not exists('customNotificationTypes', '.notiftype-meta.xml', m): bad(f'manifest notification type missing: {m}')
for m in listed.get('ValidationRule', set()):
    o, r = m.split('.')
    if not os.path.exists(f'{D}/objects/{o}/validationRules/{r}.validationRule-meta.xml'): bad(f'validation rule missing: {m}')
for m in listed.get('CustomMetadata', set()):
    if m.endswith('.*'): continue
    if not exists('customMetadata', '.md-meta.xml', m): bad(f'custom metadata record missing: {m}')
for p in g(D + '/customMetadata/*.md-meta.xml'):
    n = os.path.basename(p).replace('.md-meta.xml', '')
    if not (n in listed.get('CustomMetadata', set()) or n.split('.')[0] + '.*' in listed.get('CustomMetadata', set())): bad(f'custom metadata {n} not in manifest')
for c in [os.path.basename(p)[:-4] for p in g(D + '/classes/*.cls')]:
    if c not in listed.get('ApexClass', set()): bad(f'core class {c} not in manifest')
for c in listed.get('ApexClass', set()):
    if not os.path.exists(f'{D}/classes/{c}.cls'): bad(f'manifest ApexClass missing: {c}')
for kind, dr in (('Flow', 'flows'), ('PermissionSet', 'permissionsets'), ('Queue', 'queues')):
    if '*' not in listed.get(kind, set()): bad(f'manifest should use wildcard for {kind}')
    if not g(f'{D}/{dr}/*'): bad(f'no {kind} files found')

# 5. Picklist constants vs metadata
const = read(D + '/classes/SupportConstants.cls')
def picklist(obj, fld):
    root = ET.parse(f'{D}/objects/{obj}/fields/{fld}.field-meta.xml').getroot()
    return [v.find('m:fullName', ns).text for v in root.iter('{%s}value' % ns['m']) if v.find('m:fullName', ns) is not None]
def const_values(prefix):
    return re.findall(r"public static final String (%s\w*) = '([^']*)';" % prefix, const)
groups = [('CAT_', 'Case', 'Issue_Category__c'), ('PRIORITY_', 'Case', 'AI_Recommended_Priority__c'),
          ('SENT_', 'Case', 'Sentiment__c'), ('REASON_', 'Case', 'Escalation_Reason__c'),
          ('TYPE_', 'AI_Interaction_Log__c', 'Interaction_Type__c'), ('OUTCOME_', 'AI_Interaction_Log__c', 'Outcome__c'),
          ('SOURCE_', 'AI_Interaction_Log__c', 'Source__c')]
for prefix, obj, fld in groups:
    vals = {v for _, v in const_values(prefix)}
    if not vals: bad(f'no constants with prefix {prefix}'); continue
    meta = set(picklist(obj, fld))
    for v in vals - meta:
        bad(f'constant {v!r} ({prefix}) is not a value of {obj}.{fld}')
    for v in meta - vals:
        bad(f'picklist value {v!r} of {obj}.{fld} has no constant')

# 6. LWC apex imports
ctrl_methods = {}
for p in apex:
    s = read(p); cls = os.path.basename(p)[:-4]
    ctrl_methods[cls] = set(re.findall(r'@AuraEnabled[^\n]*\n\s*public static [\w<>\.,\s]+? (\w+)\(', s))
for p in g(D + '/lwc/*/*.js'):
    for cls, meth in re.findall(r"from '@salesforce/apex/(\w+)\.(\w+)'", read(p)):
        if meth not in ctrl_methods.get(cls, set()): bad(f'{os.path.basename(p)} imports {cls}.{meth}, no @AuraEnabled method found')

# 6b. Apex lint for mistakes the offline parser cannot catch (found by a real deploy)
RESERVED_AS_NAME = {'limit', 'offset', 'select', 'from', 'where', 'group', 'order', 'having', 'list', 'map', 'set', 'new', 'class', 'static', 'final', 'null', 'this', 'super', 'return', 'when', 'transaction', 'trigger'}
for p in apex:
    stripped = re.sub(r"'[^'\n]*'", "''", re.sub(r'//.*', '', read(p)))
    for n in re.findall(r'\b(?:Integer|String|Boolean|Id|Decimal|Long|Object|Date|Datetime|List<\w+>|Set<\w+>)\s+(\w+)\s*[=;,)]', stripped):
        if n.lower() in RESERVED_AS_NAME: bad(f'{os.path.basename(p)}: reserved word used as variable name: {n}')
        if n.endswith('_') or '__' in n: bad(f'{os.path.basename(p)}: invalid Apex identifier: {n}')

# 7. Policy
for p in apex:
    s = read(p)
    if re.search(r'SeeAllData\s*=\s*true', s, re.I): bad(f'SeeAllData used in {p}')
    if re.search(r"'[a-zA-Z0-9]{3}[0-9A-Za-z]{12}(?:[0-9A-Za-z]{3})?'", s) and re.search(r"'(00|50|0[0-9A-Z]{2})[0-9A-Za-z]{12,15}'", s):
        bad(f'possible hard-coded record Id in {p}')
if problems:
    print(f'{len(problems)} problem(s):'); [print(' -', x) for x in problems]; sys.exit(1)
print(f'OK: {len(apex)} Apex classes, {sum(len(v) for v in fields.values())} fields, manifest and constants consistent.')
