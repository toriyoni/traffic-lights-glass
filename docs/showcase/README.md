# v1.0.0 展示素材

用于仓库首页与 GitHub Release 的三段 GIF 和两张静态图。

| 素材 | 展示内容 |
| --- | --- |
| [flow.gif](v1.0.0/flow.gif) | 连续换灯、单灯放大、轻微吸附与胶囊伸展 |
| [reveal.gif](v1.0.0/reveal.gif) | 隐藏式红绿灯从原位展开、离开后收回 |
| [light.gif](v1.0.0/light.gif) | 黄灯微动、指针柔光与局部边缘反光 |
| [appearance.png](v1.0.0/appearance.png) | 浅色、深色的原生玻璃与彩色按钮 |
| [window-menu.png](v1.0.0/window-menu.png) | 与放大绿灯对齐的窗口菜单 |

## 录制来源

- 生产代码：`v1.0.0` / `0c11bd8ff34e830d312e4aaeb4369b27e5e381f6`；本次展示文档没有改变应用实现。
- Apple Silicon，macOS 27.2.1，macOS 26.5 SDK。
- 展示窗口直接使用生产的 `GlassGroupPanel`、`GlassGroupLayout`、缩放与收放状态、指针光照和 `ZoomMenuPanel`。没有用动画软件重画玻璃、补帧或放大实际吸附量。
- 为便于观察，按钮采用设置支持的 **36 pt** 尺寸；放大倍率、吸附距离及动画时间使用生产代码原值。
- 浅色与深色并排展示。背景卡片和说明文字仅为文档排版，不是应用窗口的一部分。
- 指针轨迹预设后传入组件，不向系统注入鼠标事件，不操作用户的窗口。菜单图是原生菜单组件展示，可用命令由示例快照提供；实际使用时按目标应用的能力启用。
- 以系统录屏记录实际原生渲染。GIF 输出 **840 × 330、50 fps、7.6 秒、无限循环、1× 原速**；每帧时长为 GIF 可精确表示的 20 ms。静态图保留 Retina 分辨率。
- 录制期间逐帧检查承载窗口固定、按钮实际中心与生产布局一致。素材用于展示指定版本的交互，不代替跨设备兼容性测试。

## 重新录制

需要能运行原生 Liquid Glass 的 macOS，以及项目的原生构建环境。先构建当前 debug 模块，再编译文档专用录制工具：

```sh
swift build --scratch-path .build/native-test
python3 scripts/showcase/build.py
```

如需选择 SDK，给以上两步设置同一个 `SDKROOT`。依赖配置与常规本机构建相同。

顺序录制，避免展示窗口相互遮挡：

```sh
for scene in flow reveal light; do
  .build/showcase/showcase "$scene" ".build/showcase/$scene.mov"
  .build/showcase/export ".build/showcase/$scene.mov" "docs/showcase/v1.0.0/$scene.gif"
done
.build/showcase/showcase appearance docs/showcase/v1.0.0/appearance.png
.build/showcase/showcase menu docs/showcase/v1.0.0/window-menu.png
```

工具只链接生产代码，入口为文档专用宿主。它不会运行应用主入口、安装应用、修改偏好或上传素材。录制时请勿在展示窗口内移动系统指针；原始 MOV 保存在忽略的构建目录内。
