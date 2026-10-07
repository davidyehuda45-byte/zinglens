## What changed

## Verification

- [ ] `zig build` passes
- [ ] `zig build test` passes
- [ ] Tested on: (sample project + file count)
- [ ] JSON output still valid (`--json` + parse check)
- [ ] Docs updated (CLI.md / README / CHANGELOG as needed)
- [ ] No secrets in diff (scanner masks, but verify fixtures use `ziglens-ignore`)

## Definition of Done checklist (per feature)

Unit tests, CLI + `--json` if user-facing, error handling, security review,
no regression in existing analysis.
