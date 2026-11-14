# Traffic Lights Glass

让 macOS 窗口红绿灯顺着你的指针动起来。原生液态玻璃、恰到好处的放大，还有每次划过时轻巧、连贯的回应。

[![CI](https://github.com/toriyoni/traffic-lights-glass/actions/workflows/ci.yml/badge.svg)](https://github.com/toriyoni/traffic-lights-glass/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/toriyoni/traffic-lights-glass)](https://github.com/toriyoni/traffic-lights-glass/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[下载最新版 / Download](https://github.com/toriyoni/traffic-lights-glass/releases/latest) · [发行说明](docs/releases/1.0.0.md) · [隐私说明](PRIVACY.md) · [构建与发行](BUILD-LIQUID-GLASS.md)

## 指到哪里，哪里回应

指向一颗灯，它就轻轻放大、向指针靠近。滑向下一颗时，放大状态自然接续，胶囊也随之伸展。按钮之间保留视觉上的留白，横向移动时的响应却是连续的。

![浅色和深色模式下，指针连续划过红黄绿灯：单灯放大、轻微吸附，胶囊平滑伸展](docs/showcase/v1.0.0/flow.gif)

## 轻轻靠近，从容收放

开启隐藏式红绿灯后，胶囊从窗口原本的小按钮位置展开；离开时，轻轻收回。先快后慢的节奏让响应及时，落点平稳，指针更容易跟上按钮的位置。

![指针靠近时从原位展开，离开时平滑收回；演示包含连续进入与离开](docs/showcase/v1.0.0/reveal.gif)

## 一束柔光，跟着指针走

柔和的光照同时落在按钮和胶囊上。靠近边缘时，局部反光随之亮起；轻轻移动，按钮和胶囊也有细微的随动。

![指针在灯内和胶囊边缘移动，柔光跟随，局部边缘反光增强](docs/showcase/v1.0.0/light.gif)

## 浅色或深色，都自然融入

玻璃材质与彩色按钮适应浅色、深色外观。透明度默认跟随系统 Liquid Glass 设置，也可以在应用中固定为清透效果。

![浅色和深色外观中的原生液态玻璃胶囊、彩色按钮和边缘高光](docs/showcase/v1.0.0/appearance.png)

停在绿灯上，窗口菜单会出现在绿灯旁。朝菜单移动时留有进入余量，菜单位置保持稳定，方便接着选择窗口布局。

![浅色和深色的窗口布局菜单，箭头对齐放大的绿灯](docs/showcase/v1.0.0/window-menu.png)

<sub>以上素材来自 v1.0.0 原生组件在 macOS 27.2.1 上的本机录制，使用预设指针轨迹；GIF 以 50 帧/秒、1× 原速播放。演示按钮尺寸为 36 pt，可在设置中调整。菜单可用项依目标应用而定。[素材与录制说明](docs/showcase/README.md)</sub>

## 更多功能

- 应用名单设置优先于全局开关，可单独禁用某个应用的红绿灯放大。
- 菜单支持系统可用的平铺、排列和全屏操作；进入保护不拦截其他控件和窗口的点击。
- “透明度跟随系统”默认开启，系统“降低透明度”辅助功能仍有效。
- 按钮大小 18–48 pt、独立按钮动作、隐藏式红绿灯、Dock 点击最小化、台前调度关闭按钮。
- 简体中文与英文界面；软件更新直接连接本仓库的 GitHub Releases。

当前只保留液态玻璃外观，旧圆形和贴边方块配置会自动迁移。此前的开发和验证记录见 [docs](docs)。

## 下载与安装

在 [Releases](https://github.com/toriyoni/traffic-lights-glass/releases/latest) 选择适合芯片的安装包：

| Mac | 文件名后缀 |
| --- | --- |
| Apple Silicon / M 系列 | `-arm64.dmg` 或 `-arm64.zip` |
| Intel | `-x86_64.dmg` 或 `-x86_64.zip` |

1. 打开 DMG，将 **Traffic Lights Glass.app** 拖入“应用程序”；ZIP 用户解压后把应用移入“应用程序”。
2. 启动应用，在“系统设置 → 隐私与安全性 → 辅助功能”中授予权限。
3. 从菜单栏进入设置。隐藏菜单栏图标后，重新打开应用即可进入设置。

首发采用 ad-hoc 签名，**尚未进行 Apple 公证**。首次下载打开可能被系统拦截；确认来源后请按 [Apple 官方说明](https://support.apple.com/102445) 操作，不需要关闭 SIP 或全局 Gatekeeper。每个 Release 提供 `SHA256SUMS.txt`，应用内更新还会验证独立的 Ed25519 签名。

## 软件更新

设置中的“检查更新…”和菜单栏中的同名入口均可用。默认定期检查更新，后台下载默认关闭，可在设置中开启。

更新清单和安装包全部托管在本仓库 Release，按芯片类型分别提供。更新不会连接原版 Traffic Lights+ 的更新源。私钥保存在维护者的本机钥匙串，更新清单和归档均须通过内置公钥验证。

## 系统要求与已知限制

- macOS 13+；**原生 Liquid Glass 需要 macOS 26+**，较早版本使用后备材质。
- 需要标准 macOS 辅助功能窗口按钮。部分自绘标题栏、远程软件窗口可能不兼容，可用应用名单单独关闭。
- 全屏窗口中的覆盖层仍在开发中；菜单的进入全屏命令可用。
- 原生高光与系统玻璃透明度覆盖有少量非公开兼容处理，已隔离在相关代码中，后续 macOS 更新需复测。
- 当前本机视觉验证环境为 Apple Silicon / macOS 27.2.1；自动检查与架构验证不等于所有 Mac、显示器和第三方应用均已人工测试。

## 构建

使用匹配的 Xcode 26 / macOS 26 SDK 或更新版本：

```sh
git clone https://github.com/toriyoni/traffic-lights-glass.git
cd traffic-lights-glass
bash Build-Liquid-Glass.command
open "build/Traffic Lights Glass.app"
```

构建脚本验证原生玻璃 SDK、运行测试、构建并签名应用。发布包生成、独立签名、双架构验证及 Release 草稿流程见 [构建与发行](BUILD-LIQUID-GLASS.md)。

## English

Traffic Lights Glass enlarges macOS window controls inside a native Liquid Glass capsule. It provides independent button magnification, subtle pointer attraction, pointer lighting, an anchored window-layout menu, per-app overrides, and a switch to follow the system glass appearance.

The previews above show the native v1.0.0 components in light and dark appearances: continuous hover transitions, gentle expansion and return, and light that follows the pointer. Recorded on macOS 27.2.1 with scripted pointer paths and 36 pt controls; GIFs play at their original speed at 50 fps.

Download **arm64** for Apple Silicon or **x86_64** for Intel from [Releases](https://github.com/toriyoni/traffic-lights-glass/releases/latest). Move the app into Applications and grant Accessibility access. macOS 13+ is required; native Liquid Glass requires macOS 26+.

The first release is ad-hoc signed and **not Apple-notarized**. Refer to [Apple's official first-launch guidance](https://support.apple.com/102445) if needed. Updates use this repository's GitHub Release assets and require independently signed feeds and archives. Automatic checks are enabled by default; automatic downloads are optional.

The app performs window and pointer processing locally. It contains no analytics or advertising. See [Privacy](PRIVACY.md) for the ordinary network metadata involved in update requests.

## License and attribution

基于 [Liu223344 / Traffic Lights+](https://github.com/Liu223344/traffic-light-plus) 开发，保留原项目 MIT 许可证与署名。更新框架来自 [Sparkle](https://sparkle-project.org/)，其许可证同时包含在源码和应用资源内。

Based on Traffic Lights+ by Liu223344. The original [MIT license](LICENSE) and attribution are retained. Sparkle's license is included in [Resources/Sparkle-LICENSE.txt](Resources/Sparkle-LICENSE.txt) and the distributed app.
