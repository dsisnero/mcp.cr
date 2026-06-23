# PR Workflow

## Before committing

1. **Run quality gates** (see `plans/parity.md`):
   ```bash
   crystal tool format --check src spec
   ameba src spec
   crystal spec
   crystal spec -Dpreview_mt -Dexecution_context   # MT-safety gate
   ```

2. **Update documentation**. If the change adds, changes, or removes a user-visible
   feature, API, or behavior, update all relevant docs in the same commit:

   - `CHANGELOG.md` — add an entry under the appropriate version heading
   - `README.md` — add or update usage examples
   - `docs/*` — update workflow or architecture docs if the change affects conventions
   - `plans/parity.md` — mark completed features, update descriptions, note resolved issues

## Commit conventions

- Feature commits: `port: <feature name>` with a bullet list of what was implemented
- Plan/doc commits: `docs: <what>` for plan reconciliation or doc-only changes
- Release commits: `chore: release vX.Y.Z`

## Feature workflow (red-green TDD)

For each feature from `plans/parity.md`:

1. Read the upstream source (Go `vendor/mcp-golang`, Rust `vendor/rmcp`)
2. Write a failing spec (RED)
3. Implement the smallest change that turns it green (GREEN)
4. Run quality gates
5. Update `plans/parity.md` to mark the feature done
6. Commit with `port:` prefix

## Opening a PR

1. Push the feature branch
2. Create a PR with a summary of what changed, a verification command to reproduce
   the spec run, and a note about any parity plan updates.
3. All quality gates must pass on the branch.
