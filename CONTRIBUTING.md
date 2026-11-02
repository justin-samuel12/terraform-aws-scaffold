# Contributing

Every change is a pull request, reviewed before it lands. Applies are made by a
person, never on merge.

Before asking for review, `make check` passes: formatting, lint, tests,
validation of every stack, and every stack's and example's files planned against
a mocked AWS ([conventions](docs/conventions.md#checks)). It needs no
credentials.

## Commits

`.github/hooks/commit-msg` enforces the format:

```
<type>(<optional-scope>): <description>
```

Types are exactly `terraform`, `infra`, `docs`, `ci`. The header is 72
characters or fewer. `git revert` and merge messages are accepted as git writes
them.

Commit messages, trailers and pull requests name people, never tools: no
`Co-Authored-By:` for an AI assistant, no "Generated with" footers.

Install the hooks once per clone: `make hooks`.

## Documentation

Updating the docs is part of the change, not a follow-up. One fact lives in one
place: code carries a one-line pointer to the doc that explains it.

| You changed | Update |
|---|---|
| A stack, or the layout | docs/architecture.md |
| A naming, tagging or version rule | docs/conventions.md |
