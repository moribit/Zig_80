# デバッガとブレークポイント

[目次](README.ja.md) | [English](debugger.md)

CLI Debuggerは`step/s`、`continue/c`、`registers/r`、`memory/m <address> <length>`、`disasm <address> <count>`、`break <address>`、`delete <address>`、`input <value>`、`screen`、`reset`、`quit/q`に対応します。数値は10進または小文字`0x` Prefixの16進です。

CLI ContinueはHALT、Address Breakpoint、Error、または内部の100万命令Sliceで停止します。TUIは共有DebugSessionのStep Snapshotと協調実行Loopを利用します。

実装済みはAddress Breakpointだけです。Label、条件、Hit Count、Enable/Disable、Temporary Breakpoint、Read/Write WatchpointはRoadmap項目です。

