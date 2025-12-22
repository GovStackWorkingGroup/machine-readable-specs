# GovStack machine-readable specifications

This project maps and denotes the necessary entities for the publication of GovStack specifications. It is composed of:

- JSON Schemas in the `schemas/` folder, from which implementations can create valid objects
- An ontology in the form of a `relationships.jsonld` file that describes how instances created from the json-schemas can be related to each other
- Support templates for creating objects in the `templates/` folder
- Data sets in the `data/` folder (YAML/JSON) that use the schemas
- Utility scripts (so far Ruby only) that generates templates and validates `.yml` and `.json` files against the JSON Schemas
- A documentation folder to gather research, use cases, and other documentation

This approach is meant to separate the syntatic (json schemas) and semantic (json-ld) to validate instances of the data <a name="1">1</a>


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

