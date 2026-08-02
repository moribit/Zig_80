# デバッガとブレークポイント

[目次](README.ja.md) | [English](debugger.md)

CLI Debuggerは`step/s`、`continue/c`、Register/Memory/Disassembly確認、`input`、`screen`、`reset`、終了に対応します。数値は10進または小文字`0x` Prefixの16進です。

CLI ContinueはHALT、Address Breakpoint、Error、または内部の100万命令Sliceで停止します。TUIは共有DebugSessionのStep Snapshotと協調実行Loopを利用します。

Breakpoint構文は`break [address] [if] <register-or-flag> <operator> <value> [hit N]`です。Address省略時は現在PCで、`temporary`、`delete`、`enable`、`disable`にも対応します。Operatorは`== != < <= > >=`、Flagは`S/Z/H/PV/N/C == 0|1`です。

Watchpointは`watch read|write <address[..end]> [if value <operator> N]`です。将来I/O向けに`io-read`/`io-write`も受理します。CLI/TUIは同じ`DebugSession` APIを使います。Label解決は共通Symbol Phaseで追加します。
