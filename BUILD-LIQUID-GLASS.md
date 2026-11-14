# 构建与发行 Traffic Lights Glass

## 本机构建

需要匹配的 Xcode 26 / macOS 26 SDK 或更新版本。Swift Package Manager 固定使用 Sparkle 2.9.2。

```sh
bash Build-Liquid-Glass.command
```

脚本检查原生玻璃 API、运行测试、构建并签名 `build/Traffic Lights Glass.app`，不会自行安装应用。`TARGET_ARCH=arm64` 或 `TARGET_ARCH=x86_64` 可用于指定架构；`SDKROOT` 可选择与当前编译器匹配的 SDK。

发布版继续使用 `app.trafficlightsplus.glass.local` 标识，保持已有定制版的设置和辅助功能授权。产品名称为 Traffic Lights Glass，内部 Swift 模块名保留 TrafficLightsPlus。版本号由 `Info.plist` 管理；内部构建号必须严格递增，首发为 1.0.0 / build 10，先前开发版继承的构建号为 9。

## 更新链路

按架构分别读取：

- `https://github.com/toriyoni/traffic-lights-glass/releases/latest/download/appcast-arm64.xml`
- `https://github.com/toriyoni/traffic-lights-glass/releases/latest/download/appcast-x86_64.xml`

每个清单指向对应版本的固定 ZIP 附件。GitHub 的 latest/download 地址只跟随正式发布的最新版本，草稿不会成为更新渠道。不依赖 GitHub Pages，也不把维护者的 GitHub 登录信息打包进应用。

`SUPublicEDKey` 为本项目独立的 Ed25519 公钥。私钥留在 macOS 登录钥匙串中，Sparkle account 为 `app.trafficlightsplus.glass.local`。`SURequireSignedFeed` 和 `SUVerifyUpdateBeforeExtraction` 开启，清单和归档都要验证。请保管并备份钥匙串；当前无 Developer ID 证书，丢失更新私钥后不能依赖 Apple 签名进行无缝密钥轮换。不要把私钥提交到仓库或写入发行附件。

## 准备一个版本

1. 修改 `Info.plist` 的显示版本和内部构建号。
2. 写好 `docs/releases/<version>.md`，保留系统要求与已知限制。
3. 提交并同步源码，确保工作区干净。
4. 在持有发布钥匙串的 Mac 执行：

```sh
scripts/prepare-release.sh
```

脚本运行测试，分别构建 arm64 / x86_64 应用，制作 ZIP / DMG，生成带内嵌发行说明的签名清单，验证公钥、签名、包大小、版本、架构、bundle ID 和代码签名，生成 SHA256 校验文件。结果位于 `build/releases/v<version>/`。签名使用本机钥匙串，不导出私钥，也不上传任何文件。

新维护环境需要先在 Sparkle 工具中导入原发布钥匙串；生成一把新钥匙并替换公钥不会让旧用户自动信任它。普通源码构建不需要私钥，只有发布包签名需要。

## 上传和发布

确认本机验证完成后，为该源码提交创建并推送标签：

```sh
git tag -a v1.0.0 -m "Traffic Lights Glass 1.0.0"
git push origin main v1.0.0
scripts/create-release-draft.sh
```

草稿脚本校验包对应当前提交、标签、SHA256 和独立签名，并核对发布构建号递增。上传以下七个附件：两个 ZIP、两个 DMG、两个 appcast 和 `SHA256SUMS.txt`。`SOURCE_COMMIT.txt` 与本地发行说明留作构建记录。

检查 GitHub Release 草稿后发布，并确认最新清单可匿名下载、签名验证通过，再在应用内执行“检查更新…”。发布工作流只校验附件，使用只读仓库权限，不接触发布私钥或重签更新。

## Apple 签名与公证

当前环境没有 Developer ID Application 证书，首发为 ad-hoc 签名且未 Apple 公证。Sparkle 的 Ed25519 更新验证与 Gatekeeper 的首次安装信任是两件不同的事，不能把更新签名描述为 Apple 公证。

有证书后，可通过 `SIGNING_IDENTITY` 传入 Developer ID 签名身份，并完成 Apple 公证及 stapling 后再生成归档、签名清单。不可在归档已签名后改动包内容。

## 验证记录与设计背景

- [原生玻璃高光](docs/native-glass-highlight.md)、[彩色按钮](docs/native-glass-buttons.md)、[颜色校准](docs/glass-button-color.md)
- [缓出动画](docs/ease-out-capsule-animation.md)、[悬停精度](docs/precision-hover-capsule.md)、[指针照明](docs/pointer-light-and-interaction.md)
- [应用名单](docs/application-rules.md)、[透明度跟随系统](docs/system-glass-transparency.md)、[菜单进入保护](docs/menu-approach-protection.md)

历史记录保留当时的提交与验证边界，不代表每种第三方应用、系统版本和显示器组合均已通过人工测试。
