# Local HTTP API (`/api/v1/`, localhost only)

Base: `http://127.0.0.1:4173/api/v1/`. Versioned from day one; breaking
changes bump to `/api/v2/`.

| Endpoint | Content |
|---|---|
| `GET /project` | Full snapshot: health, files, dependencies, cycles |
| `GET /graph` | Directory clusters + capped nodes/edges + `truncated` |
| `GET /treemap` | Per-file LOC/complexity + group sums |
| `GET /search?q=` | File matches (cap 20) |
| `GET /files|dependencies|architecture|complexity|security|git|impact|symbols` | Snapshot alias (per-endpoint shaping roadmap) |

All JSON. No auth (localhost-only is the boundary). No CORS wide-open:
same-origin dashboard use.
