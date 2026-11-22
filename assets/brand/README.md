# App 图标源素材

`better-together-icon-source.jpg` 是用户指定的 1280×1280 图标原图，包含绿色底、红色印章、米白对勾和黄色锚点。生成时保留整幅构图，不重绘、不使用 AI。

在项目根目录执行 `python3 scripts/generate_app_icons.py`（依赖 Pillow），即可重建 iOS 和 Android 图标及 `output/brand/icon-size-proof.png` 检查图。

- iOS：按现有 AppIcon 资源目录生成所有尺寸，包括 1024×1024 App Store 图标。输出 RGB PNG，不含透明通道；不额外绘制圆角或蒙版。
- Android：旧版启动器使用各密度的完整图。自适应图标使用 108dp 画布，原图居中放入 84dp 区域，主要印章、对勾、锚点保留在 66dp 安全区域内；背景和遮罩交由系统处理。
- 原图为不透明彩色位图，不能直接用作单色图标轮廓，因此不声明 `monochrome` 资源，避免主题图标变成纯色方块。

规格依据：[Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[Android Adaptive icons](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive)。
