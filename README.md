# GovStack machine-readable specifications

This project maps and denotes the necessary entities for the publication of GovStack specifications. It is composed of:

- JSON Schemas in the `schemas/` folder, from which implementations can create valid objects
- Support templates for creating objects in the `templates/` folder
- Data sets in the `data/` folder (YAML/JSON) that use the schemas
- A Ruby support script (`scripts/schema_cli.rb`) that generates templates and validates `.yml` and `.json` files against the JSON Schemas

Although a Ruby helper is provided, any programming language can be used to build on top of these schemas and data.

## Repository structure

- `schemas/` — JSON Schemas for GovStack specification entities (e.g., person, project, publication)
- `templates/` — Starter templates (JSON/YAML) that follow the schemas
- `data/` — Example and canonical data that conforms to the schemas
- `scripts/` — Utilities, notably `schema_cli.rb` for template generation and validation
- `spec/` — Tests for the Ruby tooling

## Quick start (optional Ruby tooling)

Prerequisites: Ruby 3.1+ and Bundler.

1) Install dependencies:

```bash
bundle install
```

2) See available schemas:

```bash
bundle exec ruby scripts/schema_cli.rb list-schemas
```

3) Generate a template from a schema (YAML by default):

```bash
# YAML template for the `project` schema
bundle exec ruby scripts/schema_cli.rb template project --format yaml > templates/project.yml

# JSON template including optional fields
bundle exec ruby scripts/schema_cli.rb template project --format json --include-optional > templates/project.json
```

4) Validate one or more data files against a schema:

```bash
bundle exec ruby scripts/schema_cli.rb validate working-group data/working-groups/wallet.yml
```

## Status

Work in progress

## Contributing

- Create scripts in your language of choice to parse the schemas, create templates, and validate objects
- Populate `data/` with objects that use the appropriate schemas
- Create new schemas or refine the existing ones

Feel free to use the repository Issues to propose improvements.
