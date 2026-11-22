# 团团陪你：卡通 UI 审核提案

## 方向
用户指定参考多邻国，采用 OJO Innovation Track，Operate。参考圆润的形状语言、粗体文字、可按压按钮、角色参与的情境反馈。原创橘黄色陪伴小熊「团团」；小队成员以绿、蓝、粉变体呈现。未使用多邻国猫头鹰、logo 或插画资源。

Design Read：面向私密熟人小队的卡通陪伴型打卡应用。Energy 中高（鲜明绿主行动），Finish 精确平面（2px 轮廓），Density 中（单屏主动作），Weight 厚实（Nunito 800–950），Seriousness 轻松（圆角和角色），依据是用户明确的多邻国卡通参考。DESIGN_VARIANCE 7 / MOTION_INTENSITY 3 / VISUAL_DENSITY 4。

## 视觉系统
背景 #FFFEFB，白色内容，正文 #3E443B，辅助 #73796E。青草绿 #65BB3C 主行动，深字 #254A16，底边 #499027；橘黄 #FFB34F 角色；蓝色用于学习，暖黄用于饮食，绿色用于运动。配色同时用图形、标签、完成勾号区分类别与状态。圆角控件 14–20px，容器 20–24px，轮廓 2px。垂直按钮底边是多邻国参考中明确要求的实体按压感，属于被用户参考授权的设计选择，不在无关容器滥用。
Nunito OFL 本地字体，中文 PingFang SC / Microsoft YaHei。手机主要正文 12–15px、标题 24–28px，辅助 10–12px。字号低于正式原生默认值的密集区域是审核时需继续确认的取舍，正式实现按 Dynamic Type 调整。

## 页面
今日、拍照打卡、完成庆祝、私密小队、个人周报、我的计划。个人计划最多三个；每次最多九张图；ALL 默认；识别暂不可用仍可盖章；运动无来源则不估时长/热量；私密小队；真实计数周报，正向反馈，不引入虚拟币、公开榜或惩罚。

## 交互与适配
宽屏呈现 3 列六页审核板，860–1280 为 2 列，窄屏 1 列。?screen=today 等参数直接进入可点击单屏。有选图、分类、纪要编辑、盖章、动态、点赞、质疑说明、短码与模拟加入、计划编辑和深浅色预览。角色为可编辑 SVG 插画，图标为 Phosphor MIT 库文件。动效只有按压位移和 toast，支持 reduced-motion。原生 dialog 处理键盘焦点与 Escape。

## 官方参考
https://blog.duolingo.com/core-tabs-redesign/ （2026，已读取正文与官方页面截图）
https://blog.duolingo.com/hub/design/
Apple HIG Tab bars / Accessibility（本会话已读取官方 JSON 文档）
OJO https://github.com/touchine-ojo/OJO-Design-Skills
旧 design.duolingo.com 页面当前重定向到博客设计栏目，未声称它仍提供独立 token 文档。

## 工具边界
已用 OJO、ui-ux-pro-max、taste、Impeccable、Playwright；ui-ux-pro-max 的品类回退不适合此产品，仅采纳可访问性原则。imagegen 内置工具不可用，没有调用收费 CLI 替代，采用原创矢量插画＋浏览器渲染。未使用生成式位图。appledesign、Context7 和 websearch 不可用，直接读取官方文章替代。独立子 agent 两次 502，未取得独立审查意见。完整原型图基于浏览器，不代表原生模拟器或真机验收。

## 范围与回滚
全部为合成数据与模拟操作。未修改 Flutter、后端、数据库、正式设计系统。旧「同频」独立原型保留供比较。关闭预览或删除本目录可撤销本方案。
