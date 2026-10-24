# 第三方说明

DuoBar 的 reveal 动画引擎来自 **Lunora DuoIcon 0.1.4**（作者 Banana，包名 `iya.banana.duoicon`）。
本仓库的包是该二进制的 RootHide 重打包（`/Library` 前缀、`iphoneos-arm64e`、ad-hoc 重签），并替换了包名、品牌、设置页与图标；引擎二进制本身未修改。

`DuoBarNCGate` 为独立实现，用于在通知中心显示期间抑制该引擎的动画读取。
