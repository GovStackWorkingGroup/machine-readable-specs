# Ruby JSON Schema Validator (json-schema gem)

This repository models domain objects with JSON Schemas under `./schemas`. The current tooling focuses on **validation** using the [`json-schema`](https://github.com/ruby-json-schema/json-schema).

Supported operations:

- List available schemas
- Validate one or more data files against a schema (YAML or JSON)
- Print a requirements summary only (without validating) via `--summary-only`
- Bundle a schema (inline / collect its referenced schemas into `$defs`)
- Bulk bundle all schemas
- Generate a Graphviz DOT dependency graph of schemas

Template generation is now supported directly by the validator script.

## Ruby Version & Install

Requires Ruby `3.3.4` (see `.ruby-version`).

```bash
bundle install
```

## CLI Usage

```bash
# List available schemas (filenames in ./schemas)
bundle exec ruby scripts/schema_validator.rb list-schemas

# Validate a JSON file against a schema by name
bundle exec ruby scripts/schema_validator.rb validate specification samples/specification.json

# Validate a YAML file
bundle exec ruby scripts/schema_validator.rb validate working-group data/working-groups/wallet.yml

# Validate multiple files in one run
bundle exec ruby scripts/schema_validator.rb validate person samples/person.json other/person2.yml

# Show only the merged required keys (from top-level + allOf) without validating
bundle exec ruby scripts/schema_validator.rb validate specification samples/specification.json --summary-only

# Generate a minimal template (required fields only) in YAML
bundle exec ruby scripts/schema_validator.rb template project > tmp/project-min.yml

# Generate a minimal template in JSON
bundle exec ruby scripts/schema_validator.rb template person --format json > tmp/person-min.json

# Generate a FULL template (include optional fields)
bundle exec ruby scripts/schema_validator.rb template specification --include-optional --format json > tmp/specification-full.json

# Bulk generate templates for all schemas (JSON + YML, all fields)
bundle exec ruby scripts/schema_validator.rb generate-templates

# Only JSON templates (required only)
bundle exec ruby scripts/schema_validator.rb generate-templates --only json --required-only --out-dir tmp/templates

# Bundle a single schema (writes to stdout)
bundle exec ruby scripts/schema_validator.rb bundle specification

# Bundle a single schema to a file
bundle exec ruby scripts/schema_validator.rb bundle specification --out tmp/bundled/specification.json

# Bulk bundle all schemas into schemas/bundled/
bundle exec ruby scripts/schema_validator.rb generate-bundles

# Generate a Graphviz DOT of schema dependencies
bundle exec ruby scripts/schema_validator.rb graph --out tmp/schemas.dot

# Render with graphviz (optional)
# dot -Tpng tmp/schemas.dot -o tmp/schemas.png
```

Example output (success):

```text
Validating 1 file against schema: specification.json
Requirements: identifier, name, version, authors, publishedDate, content, workingGroup
OK: samples/specification.json
All OK (1 file)
```

Example output (failure – truncated):

```text
Validating 2 files against schema: person.json
Requirements: identifier, name
FAIL: data/people/bad_person.json
  - Required at / The property '#/email' did not exist
OK: samples/person.json
Validation failed (1 error across 2 files)
```

### Flags

- `--summary-only` – prints only the effective required keys (after flattening top-level `allOf`) and exits.

### Schema Lookup & $ref Resolution

The validator preloads every file in `./schemas` and registers multiple aliases for each schema so that common `$ref` forms resolve offline:

- Canonical `$id` (e.g. `https://example.com/schemas/person`)
- Path forms: `/schemas/person`, `/schemas/person.json`
- Local file path (`file://...` style – registered implicitly)

For a `$ref` like `https://example.com/schemas/publication` or `/schemas/publication`, the basename is matched to `schemas/publication.json`.

### Draft Meta-Schema Handling

The `json-schema` gem (v6.x) doesn’t implement draft 2020‑12 meta-validation. Our schemas declare `$schema: "https://json-schema.org/draft/2020-12/schema"`. To avoid hard failures, the validator strips that `$schema` keyword during load (skipping meta validation while preserving functional constraints). Options if strict meta-schema validation is required:

1. Downgrade `$schema` to `http://json-schema.org/draft-07/schema#` (supported by the gem) — verify no 2020‑12-only features are used.
2. Add a local copy of the 2020‑12 meta-schema and use a different library that supports it.

### Limitations / Future Enhancements

- Bundled schema emission rewrites only direct file-based `$ref` targets; remote/network refs are left untouched.
- Nested composition (`allOf` inside referenced definitions) is preserved rather than fully merged.
- Requirements summary & template generation still perform only top-level `allOf` flattening (not deep merge of validation keywords like `additionalProperties`).

### Exit Codes

- `0` – All files valid
- `2` – One or more files failed validation OR a schema/data error occurred

### Adding New Schemas

Place the file in `./schemas/<name>.json` and set a unique `$id` (recommended: `https://example.com/schemas/<name>`). Use consistent basename so `$ref` paths resolve.

### Troubleshooting

- Missing `$ref` resolution: ensure referenced schema filename matches basename of `$ref` path.
- Graph missing edges: only `$ref` values that include `/schemas/` are considered inter-schema edges; internal `#/$defs/...` refs are intentionally ignored.
- Unexpected pass: remember meta-schema validation is skipped (strip `$schema`).
- Performance issues with large arrays: consider adding `minItems` / `maxItems` to constrain validation time.

## Content Formats (Rich Text)

When a schema field is expected to hold rich text (Markdown / HTML), prefer:

```jsonc
{
  "content": "# Heading\nBody text...",
  "contentFormat": "text/markdown"
}
```

Allowed formats (recommendation): `text/markdown`, `text/html`, `text/plain`.

---

Need deeper merging (nested allOf / anyOf) or bundled schema export? Open an issue describing desired output and we can add a companion script.


