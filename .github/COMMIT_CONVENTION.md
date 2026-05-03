# Commit Convention — Volcán Migration

This repository follows [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) per **Constitution §IX.3**.

## Format

```text
<type>(<optional scope>): <subject>

<optional body>

<optional footer>
```

- `<type>` is required and lowercase.
- `<scope>` is optional; when present, prefer the module touched (`export`, `import`, `oauth`, `drive`, `archive`, `ui`, `ci`, `docs`, ...).
- `<subject>` is in imperative mood, lowercase first letter, no trailing period, ≤ 72 chars.
- The body explains the **why**, not the **what**. The diff already shows the what.
- The footer carries `BREAKING CHANGE:` or `Closes #NN` / `Refs T102b`.

## Allowed types

| Type       | Use it for                                                                         |
|------------|------------------------------------------------------------------------------------|
| `feat`     | A new user-visible feature.                                                        |
| `fix`      | A bug fix.                                                                         |
| `docs`     | Documentation-only changes (`README`, `readme.txt`, `CHANGELOG`, `specs/`, ...).   |
| `chore`    | Tooling, build, or housekeeping that is neither a feature nor a bug fix.           |
| `refactor` | Code change that neither fixes a bug nor adds a feature.                           |
| `test`     | Adding or correcting tests.                                                        |
| `ci`       | Changes to GitHub Actions workflows or other CI/CD configuration.                  |
| `style`    | Formatting / whitespace / lint-only fixes that do not change behavior.             |

## Examples

```text
feat(export): add per-site Drive folder resolver
```

```text
fix(import): preserve PHP-serialized object lengths after URL rewrite

Length-prefixes were being recomputed in bytes for the new URL but the
nested `s:` tokens were still using the old byte length. This caused
intermittent unserialize failures on the destination site.

Closes #42
```

```text
test(archive): add malformed-archive rejection vectors

Refs T101a
```

```text
chore(ci): bump phpunit to 9.6 in matrix
```

```text
refactor(ajax): extract capability+nonce check into AjaxHandler base
```

## Special prefixes (project-specific, override Conventional types)

- `constitution:` — for `.specify/memory/constitution.md` amendments. Required by §IX of the constitution and reviewed before merge.

## Breaking changes

A commit that breaks public surface area MUST include `BREAKING CHANGE:` in the footer **and** an exclamation mark after the type:

```text
feat(api)!: rename volcanmig_archive_chunk_bytes filter to volcanmig_archive_chunk_size

BREAKING CHANGE: The filter `volcanmig_archive_chunk_bytes` is renamed
for consistency with the upload chunk filter. Re-bind any code that
listens on the old name.
```

## What this enables

- Auto-generated `CHANGELOG.md` entries from commits.
- Automatic semver bump suggestions on release (feat → minor, fix → patch, breaking → major).
- Easier code archaeology for future debugging.

## What this is NOT

- A way to gatekeep contributions. If a contributor proposes a perfect change with a non-conformant message, fix the message in the merge commit; do not bounce the PR.
