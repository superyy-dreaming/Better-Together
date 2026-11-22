from pathlib import Path

from PIL import Image
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/pdf/better-together-demo-guide.pdf"
W, H = A4
RICE = colors.HexColor("#F6F0E4")
GREEN = colors.HexColor("#21483C")
GREEN2 = colors.HexColor("#6E8C78")
RED = colors.HexColor("#C55445")
YELLOW = colors.HexColor("#E9C75F")
INK = colors.HexColor("#2F302B")
MUTED = colors.HexColor("#6E716A")
WHITE = colors.HexColor("#FFFDF7")

pdfmetrics.registerFont(
    TTFont("Heiti", "/System/Library/Fonts/STHeiti Medium.ttc", subfontIndex=0)
)

SHOTS = {
    "today": ROOT / "output/qa/ios-today-light.png",
    "team": ROOT / "output/qa/ios-team-light.png",
    "plans": ROOT / "output/qa/ios-plan-editor.png",
    "preview": ROOT / "output/qa/ios-batch-classic-preview.png",
    "grouped": ROOT / "output/qa/ios-batch-classic-grouped.png",
    "stamped": ROOT / "output/qa/ios-batch-classic-stamped.png",
    "report": ROOT / "output/qa/ios-report-light.png",
    "appearance": ROOT / "output/qa/ios-appearance-choices-classic-light.png",
    "tuantuan": ROOT / "output/qa/ios-appearance-choices-tuantuan-light.png",
}


class Guide:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.c = canvas.Canvas(str(path), pagesize=A4)
        self.page = 0

    @staticmethod
    def wrap(text: str, size: float, width: float):
        lines = []
        for paragraph in text.split("\n"):
            if not paragraph:
                lines.append("")
                continue
            line = ""
            used = 0.0
            for char in paragraph:
                step = size * (0.55 if ord(char) < 128 else 1.0)
                if line and used + step > width:
                    lines.append(line)
                    line, used = "", 0.0
                line += char
                used += step
            if line:
                lines.append(line)
        return lines

    def text(self, x, y, text, size=11, color=INK, width=470, leading=None):
        leading = leading or size * 1.55
        self.c.setFont("Heiti", size)
        self.c.setFillColor(color)
        for line in self.wrap(text, size, width):
            self.c.drawString(x, y, line)
            y -= leading
        return y

    def bullet_list(self, x, y, items, width=470, size=11, gap=6):
        for item in items:
            self.c.setFillColor(RED)
            self.c.circle(x + 3, y + 4, 2.5, fill=1, stroke=0)
            y = self.text(x + 14, y, item, size=size, width=width - 14)
            y -= gap
        return y

    def header(self, title, kicker=None):
        self.c.setFillColor(RICE)
        self.c.rect(0, 0, W, H, fill=1, stroke=0)
        self.c.setFillColor(GREEN)
        self.c.rect(0, H - 34, W, 34, fill=1, stroke=0)
        self.c.setFillColor(WHITE)
        self.c.setFont("Heiti", 8)
        self.c.drawString(42, H - 22, "BETTER TOGETHER  /  DEMO GUIDE")
        self.c.setFillColor(GREEN)
        self.c.setFont("Heiti", 24)
        self.c.drawString(42, H - 78, title)
        if kicker:
            self.c.setFillColor(RED)
            self.c.setFont("Heiti", 10)
            self.c.drawString(42, H - 98, kicker)
        self.c.setStrokeColor(YELLOW)
        self.c.setLineWidth(3)
        self.c.line(42, H - 110, W - 42, H - 110)

    def footer(self):
        self.c.setStrokeColor(colors.HexColor("#D9D0BF"))
        self.c.setLineWidth(0.6)
        self.c.line(42, 36, W - 42, 36)
        self.c.setFillColor(MUTED)
        self.c.setFont("Heiti", 7)
        self.c.drawString(
            42,
            22,
            "本 PDF 使用本地演示合成数据，不代表真实用户、真实模型准确率或真实运营指标。",
        )
        self.c.drawRightString(W - 42, 22, f"{self.page:02d}")

    def image(self, path, x, y, w, h, pad=0):
        if not path.exists():
            return
        try:
            iw, ih = Image.open(path).size
        except Exception:
            return
        scale = min((w - 2 * pad) / iw, (h - 2 * pad) / ih)
        dw, dh = iw * scale, ih * scale
        self.c.setFillColor(WHITE)
        self.c.roundRect(x, y, w, h, 10, fill=1, stroke=0)
        self.c.drawImage(
            ImageReader(str(path)),
            x + (w - dw) / 2,
            y + (h - dh) / 2,
            dw,
            dh,
            preserveAspectRatio=True,
            mask="auto",
        )

    def card(self, x, y, w, h, title, body, accent=GREEN2):
        self.c.setFillColor(WHITE)
        self.c.roundRect(x, y, w, h, 12, fill=1, stroke=0)
        self.c.setFillColor(accent)
        self.c.roundRect(x, y + h - 8, w, 8, 4, fill=1, stroke=0)
        self.c.setFillColor(GREEN)
        self.c.setFont("Heiti", 12)
        self.c.drawString(x + 14, y + h - 28, title)
        self.text(x + 14, y + h - 48, body, size=9, width=w - 28, leading=14)

    def new_page(self, title, kicker=None):
        if self.page:
            self.c.showPage()
        self.page += 1
        self.header(title, kicker)

    def close_page(self):
        self.footer()

    def save(self):
        self.c.save()


g = Guide(OUT)

# 1. Cover
g.page = 1
g.c.setFillColor(RICE)
g.c.rect(0, 0, W, H, fill=1, stroke=0)
g.c.setFillColor(GREEN)
g.c.rect(0, H - 150, W, 150, fill=1, stroke=0)
g.c.setFillColor(WHITE)
g.c.setFont("Heiti", 12)
g.c.drawString(48, H - 54, "BETTER TOGETHER")
g.c.setFont("Heiti", 36)
g.c.drawString(48, H - 105, "有证据的坚持，")
g.c.drawString(48, H - 145, "也有人同行。")
g.c.setFillColor(GREEN)
g.c.setFont("Heiti", 42)
g.c.drawString(48, H - 230, "演示讲解手册")
g.text(
    50,
    H - 265,
    "一款把个人计划、照片证明、小队互动和周报复盘放在一起的跨品类打卡 App。",
    size=15,
    width=490,
    leading=24,
)
g.image(SHOTS["today"], 350, 160, 190, 410)
g.image(ROOT / "output/brand/better-together-icon.png", 48, 112, 90, 90)
g.card(
    48,
    60,
    490,
    42,
    "演示声明",
    "以下成员、记录、图片和 AI 结果均为本地合成数据，仅用于产品演示。",
    RED,
)
g.close_page()

# 2. Value
g.new_page("产品价值", "把“想坚持”变成看得见的日常")
g.text(
    48,
    735,
    "Better Together 面向有计划、难坚持的人。每个人可以有自己的目标，小队只负责互相看见和回应。",
    size=15,
    width=490,
    leading=24,
)
g.card(48, 570, 155, 105, "01  定计划", "学习、运动、饮食、作息、饮水、冥想和自定义目标都可以使用不同节奏。", RED)
g.card(220, 570, 155, 105, "02  留证据", "拍照或选择照片，AI 只做归类和事实整理，用户始终拥有确认权。", GREEN2)
g.card(392, 570, 145, 105, "03  有回应", "点赞、评论、质疑、戳一下和周报让坚持被队友看见。", YELLOW)
g.image(SHOTS["team"], 48, 108, 220, 400)
g.image(SHOTS["report"], 310, 108, 220, 400)
g.text(48, 80, "核心闭环：定计划  ->  选图  ->  识别与确认  ->  盖章  ->  小队动态  ->  周报复盘", size=11, width=490)
g.close_page()

# 3. Team
g.new_page("演示小队", "五个人，五种节奏，同一个小队")
g.text(48, 735, "“把日子过好小队”固定在 Asia/Shanghai 时区。成员状态刻意分布在已完成、进行中、未开始和已补卡，方便现场讲解首页和小队页。", size=12, width=490, leading=19)
rows = [
    ("知夏", "进行中", "当前演示账号，学习和运动混合打卡"),
    ("小予", "已完成", "运动记录、点赞和普通评论"),
    ("陈一", "已完成", "学习记录和周报贡献"),
    ("林晓", "未开始", "英语计划逾期，展示戳一下"),
    ("安然", "已补卡", "饮水周期补卡和连续记录"),
]
y = 630
for i, (name, status, body) in enumerate(rows):
    g.c.setFillColor(WHITE)
    g.c.roundRect(48, y - 12, 490, 58, 10, fill=1, stroke=0)
    g.c.setFillColor([GREEN, RED, YELLOW, GREEN2, colors.HexColor("#9C79A9")][i])
    g.c.circle(76, y + 16, 18, fill=1, stroke=0)
    g.c.setFillColor(GREEN)
    g.c.setFont("Heiti", 12)
    g.c.drawString(108, y + 20, name)
    g.c.setFillColor(RED if status in ("未开始", "进行中") else GREEN2)
    g.c.setFont("Heiti", 9)
    g.c.drawString(108, y + 5, status)
    g.c.setFillColor(MUTED)
    g.c.setFont("Heiti", 8)
    g.c.drawString(205, y + 8, body)
    y -= 70
g.image(SHOTS["team"], 310, 205, 228, 350)
g.card(48, 160, 242, 90, "展示重点", "顶部成员状态、共同连续天数、小队动态和逾期卡片。", RED)
g.card(300, 80, 238, 90, "隐私口径", "私密计划仍只在当前账号可见，演示数据不进入云端。", GREEN2)
g.close_page()

# 4. Plans
g.new_page("计划系统", "不是所有目标都要按周一到周日")
g.text(48, 735, "计划页同时展示固定星期、间隔执行、周期目标和私密计划。统计按计划自己的规则计算，不把额外完成虚增为完成率。", size=12, width=490, leading=19)
plan_rows = [
    ("学习", "每天读 20 页", "固定星期", "公开给小队"),
    ("运动", "出门走一走", "每隔 2 天", "公开给小队"),
    ("饮水", "每 5 天喝够水", "每 5 天完成 3 天", "公开给小队"),
    ("饮食", "好好吃晚饭", "固定每日", "仅自己可见"),
    ("冥想", "睡前冥想 10 分钟", "每周完成 3 天", "公开给小队"),
]
y = 625
for i, row in enumerate(plan_rows):
    g.c.setFillColor(WHITE)
    g.c.roundRect(48, y - 14, 490, 58, 10, fill=1, stroke=0)
    g.c.setFillColor([GREEN, RED, colors.HexColor("#4B8B9A"), YELLOW, colors.HexColor("#8A6B9D")][i])
    g.c.circle(70, y + 15, 10, fill=1, stroke=0)
    g.c.setFillColor(GREEN)
    g.c.setFont("Heiti", 11)
    g.c.drawString(92, y + 21, row[0])
    g.c.setFont("Heiti", 10)
    g.c.drawString(165, y + 21, row[1])
    g.c.setFillColor(MUTED)
    g.c.setFont("Heiti", 8)
    g.c.drawString(165, y + 4, row[2] + "  ·  " + row[3])
    y -= 68
g.image(SHOTS["plans"], 48, 115, 205, 280)
g.bullet_list(285, 340, ["每个计划有自己的开始日期、截止时间和周期统计。", "同一天多次记录只计为一天，额外完成单独反馈。", "计划可见范围影响动态和小队统计。"], width=250, size=10, gap=8)
g.close_page()

# 5. Check-in flow
g.new_page("打卡流程", "先整理，再识别，最后盖章")
g.text(48, 735, "新的打卡流程把用户确认放在中心：照片先停在预览页，点击下一步后才开始识别，识别完成后按计划拆成多条记录。", size=12, width=490, leading=19)
for path, x, label in [(SHOTS["preview"], 48, "1 选图预览"), (SHOTS["grouped"], 214, "2 识别分组"), (SHOTS["stamped"], 380, "3 确认盖章")]:
    g.image(path, x, 350, 150, 300)
    g.c.setFillColor(GREEN)
    g.c.setFont("Heiti", 10)
    g.c.drawCentredString(x + 75, 330, label)
g.bullet_list(48, 270, ["预览页可以继续添加、删除和调整照片类型。", "学习和运动混合上传时，系统生成两条独立记录。", "单张照片可移动到其他计划，整条记录也可改计划。", "识别失败时仍可按 ALL 归档，不阻止盖章。"], width=490, size=10, gap=6)
g.close_page()

# 6. AI
g.new_page("AI 识别与纪要", "AI 是建议层，不是裁判")
g.text(48, 735, "演示页中的识别结果用于说明产品结构，不代表真实模型准确率。正式账号使用用户自己配置的 OpenAI 兼容接口，密钥只在设备安全存储。", size=12, width=490, leading=19)
g.card(48, 570, 235, 105, "归类规则", "置信度达到 80% 才参与计划建议。严格过半才归类，平票或未完成时保留 ALL。", RED)
g.card(303, 570, 235, 105, "字段来源", "运动时长只能来自截图或已有数据。饮食热量显示估算区间。每个字段标注 AI、截图读数或用户手填。", GREEN2)
g.card(48, 435, 235, 105, "摘要留存", "每张照片都有独立事实摘要，归类、手动调整和重试都不会覆盖已确认内容。", YELLOW)
g.card(303, 435, 235, 105, "失败语义", "识别超时、服务失效或未配置时，照片仍能归档盖章，纪要标记待补。", colors.HexColor("#8A6B9D"))
g.image(SHOTS["grouped"], 165, 85, 190, 310)
g.close_page()

# 7. Interactions
g.new_page("小队互动", "看见进度，也保留边界")
g.image(SHOTS["team"], 48, 150, 230, 430)
g.bullet_list(315, 600, ["正常盖章卡：可以点赞、评论和提出质疑。", "质疑未过半：记录仍保持已盖章，只显示进度。", "质疑过半：进入待重打，次日窗口内可以重新提交。", "逾期卡：只有“戳一下”，不混入点赞和评论。", "补卡记录保留补卡标记和历史轨迹。"], width=220, size=10, gap=10)
g.card(315, 170, 220, 120, "现场演示顺序", "先点开小予的正常记录，再查看林晓的待重打和逾期卡，最后展示安然的补卡记录。", RED)
g.close_page()

# 8. Reports
g.new_page("周报与分享", "把一周的坚持收成一页")
g.text(48, 735, "周报包含完成率、分类汇总、连续变化、纪要精选和下周建议。个人长图只包含本人数据，小队版只投影公开计划。", size=12, width=490, leading=19)
g.image(SHOTS["report"], 48, 160, 245, 450)
g.card(320, 550, 218, 105, "个人周报", "一小步，也算数。演示完成率 79%，包含学习 7 次、运动 4 次和三条亮点。", RED)
g.card(320, 405, 218, 105, "小队周报", "五个人共完成 23 次记录，展示分类汇总、回应数量和可分享状态。", GREEN2)
g.card(320, 260, 218, 105, "两个分享动作", "发送到小队动态，或保存只包含本人数据的图片。分享状态可在动态中继续互动。", YELLOW)
g.close_page()

# 9. Appearance
g.new_page("双外观与平台体验", "同一套业务，两种表达")
g.image(SHOTS["appearance"], 48, 230, 180, 350)
g.image(SHOTS["tuantuan"], 250, 230, 180, 350)
g.text(48, 615, "经典纸面", size=12, color=GREEN)
g.text(250, 615, "团团陪你", size=12, color=GREEN)
g.bullet_list(48, 190, ["iOS 使用系统安全区、返回手势和动态字体。", "核心触控目标保持至少 44pt。", "浅色、深色、大字号、加载和失败状态都有对应反馈。", "照片查看支持双击、双指缩放和左右切换。"], width=490, size=10, gap=8)
g.card(48, 70, 490, 62, "检查重点", "现场演示时可从设置切换外观，再打开小队和周报，观察同一数据在两套视觉中的层级变化。", RED)
g.close_page()

# 10. Script
g.new_page("现场讲解脚本", "8 分钟完成一次完整演示")
script = [
    ("00:00 - 01:00", "首页与小队", "介绍成员状态、共同连续天数和今天的计划。"),
    ("01:00 - 02:00", "灵活计划", "打开计划页，展示固定星期、间隔执行和周期目标。"),
    ("02:00 - 04:00", "混合打卡", "选入学习照片和运动截图，说明预览、下一步识别、拆条和逐图摘要。"),
    ("04:00 - 05:20", "确认与盖章", "移动一张照片、修改整条计划、编辑纪要，再完成盖章。"),
    ("05:20 - 06:30", "小队互动", "打开正常记录、质疑进度、待重打和逾期戳一下。"),
    ("06:30 - 07:20", "周报", "展示个人周报、小队周报和两个分享动作。"),
    ("07:20 - 08:00", "边界说明", "强调演示数据为合成数据，BYOK、私有照片和失败可恢复规则。"),
]
y = 700
for time, title, body in script:
    g.c.setFillColor(RED)
    g.c.setFont("Heiti", 10)
    g.c.drawString(48, y, time)
    g.c.setFillColor(GREEN)
    g.c.setFont("Heiti", 12)
    g.c.drawString(150, y, title)
    g.text(235, y, body, size=9, width=300, leading=13)
    y -= 64
g.card(48, 160, 490, 100, "演示边界", "本地模式不连接 Supabase、不发送照片到 AI、不保存 API Key。真实账号需要在设置中配置自己的兼容接口。", RED)
g.card(48, 75, 490, 58, "下一步", "若进入真实内测，使用专用测试账号和合成照片先验证权限、通知、Realtime、AI 成本和隐私说明。", GREEN2)
g.close_page()

g.save()
print(OUT)
