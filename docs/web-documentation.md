# Optional Web Documentation

Markdown in this repository remains canonical and directly readable on GitHub. Web publication is optional and must not affect `zig build`, `zig build test`, Zig_80 runtime dependencies, or `build.zig.zon`.

| Option | Setup | Multilingual/navigation/search | GitHub Pages | Maintenance |
|---|---|---|---|---|
| mdBook | low; one Rust tool outside Zig_80 | strong linear navigation/search; multilingual books usually separate | straightforward static output | small, but two book indexes/configs may be needed |
| MkDocs | moderate Python environment | strong navigation/search; plugins often used for multilingual sites | straightforward static output | plugin/version maintenance can grow |
| GitHub Pages with plain Markdown/Jekyll | lowest initial repository change | basic navigation; multilingual and search are manual | native | low tooling, more manual information architecture |

mdBook is the most natural experiment for the numbered Tutorial, while Reference and Guides need a shared navigation design. A future experiment should use optional CI only, keep all links useful in GitHub Markdown, and maintain separate English/Japanese table-of-contents files. No generator is selected or required today.

