# Better Together

Flutter iOS / Android 私密小队打卡应用。产品规则保留在项目根目录 README.md，设计规范见 ../DESIGN.md。

## 本机运行

在项目根目录执行 `bash scripts/flutter.sh run --dart-define=DEMO_MODE=true`。

演示模式使用明确标注的本地示例数据，不调用云端。正式模式需要 ../.local/client.json；配置方式见 [接入说明](../docs/setup.md)。缺少配置会显示说明页，不会自动进入演示模式。

## 验证与构建

```sh
bash scripts/flutter.sh analyze
bash scripts/flutter.sh test
bash scripts/flutter.sh build ios --simulator --dart-define=DEMO_MODE=true
bash scripts/flutter.sh build apk --debug --dart-define=DEMO_MODE=true
```

两个平台串行构建，避免生成的插件文件相互覆盖。正式 Android 包要求已有发布证书；iOS 需明确的 Apple 开发团队与 provisioning profile，详见接入说明。

## 结构

- lib/features：页面与交互
- lib/domain：数据类型及客户端规则
- lib/data：Supabase / 本机演示仓库与 Riverpod 状态
- lib/platform：推送、照片原生接入
- lib/ui：主题与通用控件
- test、integration_test：业务、页面及模拟器流程验证

授权、日期、配额、质疑阈值与数据可见性以 ../supabase 服务端实现为准，客户端校验不替代服务端。
