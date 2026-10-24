# DuoBar

Duo 风格状态栏圆环：把电量、Wi-Fi、蜂窝信号与 VPN 指示收进右侧圆环；解锁与收起控制中心时播放 reveal 动画，通知中心收起不播放。

- 包名 `com.ning.duobar`，版本 **1.1**，架构 `iphoneos-arm64e`（RootHide）
- 作者 / 维护者：**Ning**
- 设置：设置 → DuoBar（启用、电量百分比、圆环大小 / 描边 / 中心图标 / 偏移、信号 SIM、动画开关、通知中心抑制、VPN）

## 软件源

```text
https://sorenning.github.io/
```

直接下载：

```text
https://sorenning.github.io/debs/roothide/com.ning.duobar_1.1_iphoneos-arm64e.deb
```

## 结构

| 路径 | 说明 |
| --- | --- |
| `dist/` | 已构建的 deb |
| `control` / `postinst` | 打包元数据与安装脚本 |
| `prefs-Root.plist` | 设置页（简化中文页） |
| `prefs-Info.plist` / `prefs-Entry.plist` | 设置 bundle 与 PreferenceLoader 入口 |
| `src/NCGate.xm` | 通知中心动画抑制层源码 |
| `src/icons/` | 图标 1x / 2x / 3x 与 1024 母图 |

安装前先卸载旧的 `iya.banana.duoicon`，安装后 respring。
