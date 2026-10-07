# ZigLens CI/CD

Quality gates without a server:

```yaml
# .github/workflows/ziglens.yml
name: ziglens
on: [push, pull_request]
jobs:
  analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v1
        with: { version: 0.17.0 }
      - run: zig build -Doptimize=ReleaseSafe
      - run: ./zig-out/bin/ziglens analyze --ci --format json --output ziglens.json .
      - uses: actions/upload-artifact@v4
        with: { name: ziglens-report, path: ziglens.json }
```

Exit codes: `0 pass · 1 failure · 2 gate failure · 3 config error`.

Gate defaults (v0.1): fail on any cycle or `ARCH-001`. Thresholds +
baseline (`ziglens baseline create`, Phase 2) for legacy repos: only new
violations fail CI.

Pre-commit (staged-only, Phase 2): `ziglens analyze --staged`.
