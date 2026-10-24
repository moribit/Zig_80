# Zig versions / Zigバージョン

The baseline remains **Zig 0.16.0**. Source-level compatibility with the installed
0.17.0 compiler was added separately in commit `e313526` before this work:
Build.run uses `addPassthruArgs` when available; array initialization uses `@splat`;
enum iteration uses `std.enums.values` rather than the changed reflection layout.
This is compatibility, not a migration of the minimum version.

Current std.Io-based file/terminal I/O, allocators, ArrayList, formatting and testing
compile on both installed compilers. Zig 0.17 `fmt` rewrites legacy enum conversion
builtins to new names, which would break 0.16; **use 0.16 for formatting**. No such
rewrite is part of feature commits. macOS native verification is local; Linux
verification belongs to CI and must not be claimed until CI runs.

日本語: 最低バージョンは0.16.0のままです。0.17でのビルド互換対応は既存の独立コミット
`e313526` にあります。0.17のFormatterはenum変換組込みを0.16非互換の名前に
書き換えるため、整形には0.16を使用します。Linux動作はCI実行結果で確認してください。
