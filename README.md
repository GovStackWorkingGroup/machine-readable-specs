# GovStack machine-readable specifications

This project provides tooling for the publication of machine readable GovStack specifications. 

[Jump here](#application) for a practical example

It is composed of:

- JSON Schemas in the `schemas/` folder, from which implementations can create valid objects
- An supporting ontology 
- Data sets in the `data/` folder (YAML/JSON) that use the schemas
- Utility scripts (so far Ruby only) that generate templates and validates `.yml` and `.json` files against the JSON Schemas
- A documentation folder to gather research, use cases, and other documentation in `documentation/`

This approach is meant to [separate the syntatic (json schemas) and semantic (json-ld)](https://github.com/FAIRsharing/jsonldschema?tab=readme-ov-file) to validate instances of the data 

## Application

See the following for a GovStack Specification:

1) A GovStack Specification:
- belongs to a GovStack Group throughb the workingGroup attribute. This could be a uri, or urn
- Has a list of functionalities, either rendered in an embedded json or denoted by the {"type": "file|url", "path": path} json structure
- Has a list of authors (which is an instance of a Person*)
- Has a list of reviewers
- Has a list of editors
- Has a list of definitions
- Has one license, , either rendered in an embedded json or denoted by the {"type": "file|url", "path": path} json structure
- Has one publishedDate:string, which expects a string compliant  by the ISO 8601 YYYY-MM-DD date type 
- Has one api-specification, which expects an OpenApi-specification file, denoted by a simple json object of , either rendered in an embedded json or denoted by the {"type": "file|url", "path": path} json structure
- Has one releaseNotes attribute, either rendered in an embedded json or denoted by the {"type": "file|url", "path": path} json structure
- Has one version:string which must be semver compliant

2) A GovStack Functionality:

- Has a title:string
- Has a level (DRAFT, REQUIRED or UNDEFINED). DRAFT functionalities are not yet in a defined state. REQUIRED means that it has associated GovStack Requirements.

Relies on the following for relations:
- belongs to a Specification
- has a one-to-many optional requirements relation. 

3) A GovStack Requirement:
- Has a level (DRAFT, RECOMMENDED, REQUIRED or DEPRECATED, as denoted by the govspecs 2.0 strategy)
- has a description:text that contains the text definition of the requirement. a plain-text definition is encouraged.
- has a operationId:string that belongs to an open-api file for the specification. See https://spec.openapis.org/oas/latest.html#path-item-object

4) A GovStack Definition

- Has a term:string that defines what term is defined
- Has a definitionFormat:string that expect a mime/type to render the definition
- Has a definition:text that accepts the entry text.

n) A Person

- Has a name:string
- Has an affiliation, denoted by a simple json object of {"name": name, "url": url}
- May have an identifier:string but most probably it is an embedded one
- may not have a namespace

0) All objects:
Rely on the following for identification:

- Has a namespace:string serves to denote which kind of object is this. here it is pointing to a urn but it could be a schema or jsonld
- Has an identifier:string 
- Has a uri:string provisional object uri that helps to say that different objects are pointing to the same entity

## Status

Work in progress

## Repository structure

- `schemas/` — JSON Schemas for GovStack specification entities (e.g., person, project, publication)
- `templates/` — Starter templates (JSON/YAML) that follow the schemas
- `data/` — Example and canonical data that conforms to the schemas
- `scripts/` — Utilities for template generation and validation
- `documentation/` - Documentation and research resources 

## Contributing

- Create scripts in your language of choice to parse the schemas, create templates, and validate objects
- Populate `data/` with objects that use the appropriate schemas
- Create new schemas or refine the existing ones

Feel free to use the repository issues to propose improvements.


## References

[Gonzalez-Beltran, A., Sansone, S., & Batista, D. jsonldschema [Computer software]. https://github.com/FAIRsharing/jsonldschema](#1)