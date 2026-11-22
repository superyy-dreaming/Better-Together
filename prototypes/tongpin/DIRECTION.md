# 同频：独立审核原型

## 范围
Redesign - Overhaul / Operate。只创建 prototypes/tongpin，不修改 Flutter、后端或根 DESIGN.md。用户先审核交互原型，再决定生产 App 是否采用。中文，移动优先，所有内容为明确标注的示例。

## Design Read
有计划但难坚持的熟人小队，在短暂空闲中完成记录、看见同伴。用钴蓝、雾白、照片和有节奏的记录条表达“各自的节奏，共同的日常”。不延续纸面收据与橡皮章的视觉，但保留“已盖章”的产品状态。

## 决策
OJO Innovation Track，采用叙事驱动：今天的一步进入小队日常，汇成每周记录。Energy 中等：主行动、重点字和完成条使用单一钴蓝；Finish 对齐精确，不加纹理；Density 中低：主任务先行、细节滚动；Weight 中等：标题明显、正文轻；Seriousness 温和：无惩罚、无排行榜、无娱乐化数值。

DESIGN_VARIANCE 7 / MOTION_INTENSITY 3 / VISUAL_DENSITY 4，仅作为视觉重设计判断，不覆盖原生操作规范。选定方向优先于技能抽签；技能候选中的纸张印章与旧视觉过近、越野地图与机场翻牌过度依赖运动或离站隐喻，不采用其造型，吸收信息顺序与状态可追溯性。使用 code-led 路径，无生成图片工具，不声称生成了设计稿。

## FIRST VIEWPORT
左上头像和日期、右上通知和设置；两行行动标题；周历；真实运动照片上的下一步；已完成条目；同伴入口。大屏外围只提供评审导航和说明，不当作 App 的生产桌面布局。

## SIGNATURE INTERACTION
选多图 → 模拟逐图识别 → 改分类与纪要 → 短促成功反馈 → 新记录进入小队动态。打卡、评论、短邀请码、周报长图、计时和主题都有可见响应。单张旧图被剔除，全不合格才停止；AI 暂不可用可先盖章。

## 状态与边界
默认、禁用、加载、错误、空、成功、焦点与按压均可体验。照片仅本地 object URL；无 fetch、密钥存储、生产接口。真实相机扫码、AI、账户、通知和删除明确为原型示意。保留 3 个计划、9 张照片、固定时区、私密照片、来源标记、热量区间、质疑阈值。

## 适配与质量
375 / 390 px 直接展示 App；768 / 1024 px 为导航＋手机预览；1440 px 增加设计说明。深色主题、reduced-motion、键盘焦点和 dialog 原生焦点控制。Web 原型不等同于原生 HIG 合规验收，VoiceOver、原生系统手势和真实相机需后续 App 实现时验证。

## 依据及能力限制
使用已安装 OJO app-ui-ux-best-practices、ui-ux-pro-max、taste、Impeccable 与 Playwright。ui-ux-pro-max 产品检索落入不匹配的服务营销 fallback，只采用通用可访问性规则。websearch/firecrawl、Context7 与 appledesign 未提供；直接读取 Apple 官方 tab-bars/accessibility JSON 文档与 OJO GitHub README，核验 Day One/Nike 官方网页作为产品参考，Are.na 返回 403 未采用。没有声称完成大范围竞品视觉研究。独立审查 agent 调用返回 502，采用主 agent 浏览器与截图检查，非独立审查结论。
