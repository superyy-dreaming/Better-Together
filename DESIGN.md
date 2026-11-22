# Better Together 设计系统

## 方向与平台
Operate，参考适配。继承 HTML 的纸面收据 + 橡皮章，不重新进行风格投票。OJO 约束信息层级、真实资产、八态与反模板检查；Apple HIG / Material 3 优先约束平台行为。无 appledesign skill，以 Apple 官方 HIG 与 Impeccable iOS/android references 替代。OJO 的网页字体和 Tailwind 建议转换为原生字体与 Flutter Theme，不引入 Web 字体依赖。

## Tokens
浅色背景 #F6F3EA，表面 #FFFFFF，次表面 #FBF9F2，正文 #161C18，次正文 #5A665E。主操作 #173E2E，印章 #FF4A1A，黄色 #FFB81C 仅分类和有限强调。白字不得直接搭配亮朱红；章印用图形或深色文字。深色背景 #171B18，表面 #212722，正文 #F2EFE6，次正文 #A8B3AA，主操作 #7ED3A6，章印 #FF6B3D。
4/8pt 间距基线，屏幕横边距 20，组内 8–12，段间 24。卡片 18–22，控件 12–16。无装饰阴影、无伪设备边框。系统字体；数字 tabular。正文 17 iOS /16 Android，标题 28–32，辅助至少 12。

## 信息架构
今日、小队、周报、计划四个目的地；打卡是独立主操作，进入全屏任务，不伪装成选中 Tab。头像进入我的/设置，铃铛进入通知，计划可进入历史。详情使用导航堆栈；短任务采用平台 Sheet。紧凑单列、宽屏限宽或双栏；横屏和大字号不得裁切。

## 状态与动效
所有异步操作明确显示进行状态和恢复动作；未加载不同于空数据。盖章反馈是短暂 scale/opacity 与触觉，减少动态效果时只显示状态。照片、纪要、统计均使用真实用户数据，演示模式必须显式进入并标注。

## 验证
Flutter analyze/test，iOS Simulator 与 Android Emulator 的浅深色、大字体、核心操作截图；一次批量检查与一次修复确认。浏览器只作原始 HTML 参考，不作为原生验收证据。
