#!/usr/bin/env python3
"""
Offline structural check of Salesforce source-format XML against the Metadata API schema that ships inside the
Salesforce CLI (jsforce).  It verifies that every XML element name is a real property of its parent type.

It does NOT replace a real deployment validation (it cannot check org-specific values, references to other
components, or business rules).  See VALIDATION_REPORT.md.

Usage
    1. Export the schema once (path depends on where the CLI lives):
         node -e "require('fs').writeFileSync('md-schema.json', JSON.stringify(require('<...>/@jsforce/jsforce-node/lib/api/metadata/schema.js').ApiSchemas))"
    2. python3 scripts/dev/validate_metadata_schema.py md-schema.json force-app [more dirs...]
"""
import json, os, re, sys
import xml.etree.ElementTree as ET

SUFFIX_TO_TYPE = {
    '.field-meta.xml': 'CustomField', '.object-meta.xml': 'CustomObject', '.validationRule-meta.xml': 'ValidationRule',
    '.md-meta.xml': 'CustomMetadata', '.queue-meta.xml': 'Queue', '.notiftype-meta.xml': 'CustomNotificationType',
    '.permissionset-meta.xml': 'PermissionSet', '.tab-meta.xml': 'CustomTab', '.app-meta.xml': 'CustomApplication',
    '.flexipage-meta.xml': 'FlexiPage', '.flow-meta.xml': 'Flow', '.cls-meta.xml': 'ApexClass',
    '.trigger-meta.xml': 'ApexTrigger', '.js-meta.xml': 'LightningComponentBundle', '.report-meta.xml': 'Report',
    '.reportFolder-meta.xml': 'ReportFolder', '.namedCredential-meta.xml': 'NamedCredential',
}
# Elements that the source format allows but the schema lists under a different shape.
SKIP_CHILDREN = {'xmlns'}

def local(tag):
    return tag.split('}', 1)[1] if '}' in tag else tag

def base_type(t):
    if isinstance(t, list):
        return t[0]
    return t.lstrip('?')

def all_props(type_name, schema):
    """Properties of a type including everything inherited through "extends" (for example fullName from Metadata)."""
    props = {}
    spec = schema.get(type_name)
    while spec is not None:
        for k, v in spec['props'].items():
            props.setdefault(k, v)
        parent = spec.get('extends')
        spec = schema.get(parent) if parent else None
    return props

def check(elem, type_name, schema, path, errors):
    if schema.get(type_name) is None:
        return  # primitive or unknown complex type: nothing to verify
    props = all_props(type_name, schema)
    for child in elem:
        name = local(child.tag)
        if name not in props:
            errors.append(f"{path}/{name}: not a property of {type_name}")
            continue
        check(child, base_type(props[name]), schema, f"{path}/{name}", errors)

def main():
    schema = json.load(open(sys.argv[1]))
    # Metadata base type adds fullName to every type
    problems = 0
    checked = 0
    for root_dir in sys.argv[2:]:
        for dp, _, files in os.walk(root_dir):
            for f in files:
                for suffix, tname in SUFFIX_TO_TYPE.items():
                    if f.endswith(suffix):
                        p = os.path.join(dp, f)
                        try:
                            root = ET.parse(p).getroot()
                        except ET.ParseError as e:
                            print(f"FAIL {p}: XML not well-formed: {e}")
                            problems += 1
                            break
                        if local(root.tag) != tname:
                            print(f"FAIL {p}: root element is {local(root.tag)}, expected {tname}")
                            problems += 1
                            break
                        errs = []
                        check(root, tname, schema, tname, errs)
                        checked += 1
                        if errs:
                            problems += len(errs)
                            for e in errs:
                                print(f"FAIL {p}: {e}")
                        break
    print(f"\n{checked} metadata files checked, {problems} problem(s)")
    sys.exit(1 if problems else 0)

if __name__ == '__main__':
    main()
