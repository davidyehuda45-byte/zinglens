# Plugin development (local plugins, v0.5 scope)

Plugins are **untrusted by default**: review the manifest before installing.
There is no cloud registry; install from a local directory:

```powershell
ziglens plugin install ./my-plugin
ziglens plugin list
ziglens plugin remove ./my-plugin
```

## Manifest (`plugin.manifest`, in the plugin dir)

```ini
name = "my-analyzer"
version = "0.1.0"
author = "Your Name"
capabilities = "analyzer"
permissions = "none"
supported_languages = "typescript,python"
```

- `capabilities`: `analyzer`, `language`, `reporter`, `rule`, `visualization`
  (comma-separated; core v0.5 reads the manifest, execution sandbox is roadmap).
- `permissions`: declare `none`, `network`, or `fs-write` if ever needed.
  Anything beyond `none` must be justified in review.

## Roadmap

Manifest registry → capability-matched hooks (`analyzer.analyze(project) →
Finding[]`) → sandboxed execution. Until then, custom architecture rules
(`[[rules]]` in `.ziglens.toml`, see `docs/CONFIG_EXAMPLE.toml`) cover most
policy needs without code.
