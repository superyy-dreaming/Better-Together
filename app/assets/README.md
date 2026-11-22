# Better Together 本地视觉资源

## 团团插画

`tuantuan/tuantuan-{wave,camera,celebrate,read,stand}.png` 来自本项目已审核的「团团陪你」原型：

- 可编辑源文件：`prototypes/tuan-tuan/assets/tuantuan-*.svg`
- 原创生成脚本：`prototypes/tuan-tuan/assets/make-characters.py`
- 用途：Better Together 的陪伴角色，不代表小队成员身份。
- 原始画布：256 × 310；PNG：768 × 930，RGBA 透明背景，为 3 倍分辨率导出。
- 转换方式：Chromium 渲染 SVG，使用 Playwright 截图并启用 `omitBackground: true`。未加入 Flutter SVG 或浏览器运行时依赖。
- 所有插画均为本项目原创资源，不含多邻国角色、标志或插画。

## Nunito 字体

`fonts/Nunito-Bold.ttf`（700）和 `fonts/Nunito-ExtraBold.ttf`（800）为 Nunito 的静态字重实例。源文件是原型目录的 `Nunito.ttf`：

https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito%5Bwght%5D.ttf

使用 fontTools `instantiateVariableFont(font, {"wght": weight}, updateFontNames=True)` 生成对应静态字体，已移除可变字体轴。用于拉丁字母与数字；中文由平台系统字体回退显示。Flutter 中以同一字体家族注册两个文件，并分别声明 `weight: 700` 和 `weight: 800`。

字体版权属于 The Nunito Project Authors，按 SIL Open Font License 1.1 分发；完整许可附在 `fonts/Nunito-OFL.txt`。所有资源均为本地文件，运行时不请求远程字体或插画。

## 打卡演示照片

`demo/test-photos/` 为用户提供的 `better-together-test-photos.zip` 中的 20 张 AI 合成图片：学习 5 张、运动 6 张、饮食 5 张、生活兴趣 4 张。原始 JPEG 字节和元数据保持不变，SHA-256 与尺寸记录在 `manifest.json`；原对照表保存在同目录 `README.md`。

- 本地 `showcase_v3` 数据按图生成预置纪要和字段，运行时不调用 AI、不上传图片、不创建云端账号。图片与预置结果均不能作为真实模型准确率证据。
- `sport-02.jpg` 的完整日期为 2026-11-22；其星期文字与日历不一致，不采用星期标签。`sport-01.jpg` 没有完整日期，保留待核实状态。不会向原图伪写 EXIF。
- 学习图片不推断学习时长；普通运动图片不推断时长、距离、热量；生活兴趣图片保留 ALL。运动读数仅来自画面显示，饮食热量区间明确为合成演示估算。
- 旧 `study.jpg`、`dinner.jpg`、`exercise.png`、`water.png` 仅保留用于尚未显式重置的旧本地演示存档。新版示例不再引用它们。
- 重新导入：`python3 scripts/import_demo_photos.py /path/to/better-together-test-photos.zip`。脚本只读固定 20 个 JPEG 和说明文档，不执行压缩包内容。

应用图标源文件位于项目根目录 `assets/brand/better-together-icon-source.jpg`，由 `scripts/generate_app_icons.py` 导出 iOS 与 Android 原生图标；保留用户提供的完整构图。
