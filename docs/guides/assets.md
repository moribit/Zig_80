# Asset Pipeline Guide (planned)

[Index](README.md) | [日本語](assets.ja.md)

No `asset` command or `incbin` directive is implemented. Current assets must be expressed with `db`/`dw` or converted by a separate user workflow.

The planned dependency-free pipeline prioritizes PBM, text bitmap, raw binary, and CSV rather than PNG. Output candidates are raw/page-layout 1bpp bytes and generated assembly includes. See Roadmap Phase 6.

