#!/usr/bin/env python3
"""Generate the Better Together demo guide.

The guide intentionally uses synthetic demo data and the repository's existing
QA screenshots. It is a static presentation handout, not a product export.
"""

from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.lib.utils import ImageReader


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "pdf" / "better-together-demo-guide.pdf"
TMP = ROOT / "tmp" / "pdfs"
QA = ROOT / "output" / "qa"

GREEN = colors.HexColor("#1E4B3D")
GREEN_DARK = colors.HexColor("#14352C")
RED = colors.HexColor("#C35448")
YELLOW = colors.HexColor("#F1C453")
PAPER = colors.HexColor("#F6F0E3")
INK = colors.HexColor("#242A25")
MUTED = colors.HexColor("#66736B")
LINE = colors.HexColor("#D7CDBC")
WHITE = colors.HexColor("#FFFDF6")


def register_fonts() -> tuple[str, str]:
    light = "/System/Library/Fonts/STHeiti Light.ttc"
    medium = "/System/Library/Fonts/STHeiti Medium.ttc"
    if not Path(light).exists() or not Path(medium).exists():
        raise SystemExit("需要 macOS STHeiti 字体才能生成中文 PDF")
    pdfmetrics.registerFont(TTFont("BT-Light", light, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("BT-Medium", medium, subfontIndex=0))
    return "BT-Light", "BT-Medium"


FONT, FONT_BOLD = register_fonts()

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(
    name="CoverKicker", fontName=FONT_BOLD, fontSize=12, leading=18,
    textColor=YELLOW, spaceAfter=14,
))
styles.add(ParagraphStyle(
    name="CoverTitle", fontName=FONT_BOLD, fontSize=36, leading=43,
    textColor=WHITE, spaceAfter=12,
))
styles.add(ParagraphStyle(
    name="CoverSub", fontName=FONT, fontSize=17, leading=26,
    textColor=colors.HexColor("#DCE9DE"), spaceAfter=16,
))
styles.add(ParagraphStyle(
    name="H1BT", fontName=FONT_BOLD, fontSize=24, leading=31,
    textColor=GREEN_DARK, spaceAfter=9,
))
styles.add(ParagraphStyle(
    name="H2BT", fontName=FONT_BOLD, fontSize=14, leading=20,
    textColor=GREEN, spaceBefore=7, spaceAfter=5,
))
styles.add(ParagraphStyle(
    name="BodyBT", fontName=FONT, fontSize=10.3, leading=16,
    textColor=INK, spaceAfter=6,
))
styles.add(ParagraphStyle(
    name="SmallBT", fontName=FONT, fontSize=8.3, leading=12,
    textColor=MUTED, spaceAfter=4,
))
styles.add(ParagraphStyle(
    name="CaptionBT", fontName=FONT, fontSize=8.2, leading=12,
    textColor=MUTED, alignment=TA_CENTER, spaceBefore=3, spaceAfter=6,
))
styles.add(ParagraphStyle(
    name="CalloutBT", fontName=FONT_BOLD, fontSize=12, leading=19,
    textColor=GREEN_DARK, spaceAfter=4,
))
styles.add(ParagraphStyle(
    name="TableBT", fontName=FONT, fontSize=8.5, leading=12,
    textColor=INK,
))
styles.add(ParagraphStyle(
    name="TableHeadBT", fontName=FONT_BOLD, fontSize=8.5, leading=12,
    textColor=WHITE,
))


def p(text: str, style: str = "BodyBT") -> Paragraph:
    return Paragraph(escape(text).replace("\n", "<br/>") , styles[style])


def rich(text: str, style: str = "BodyBT") -> Paragraph:
    return Paragraph(text, styles[style])


def img(name: str, width: float, height: float, caption: str | None = None):
    path = QA / name
    if not path.exists():
        return [p(f"缺少演示截图：{name}", "SmallBT")]
    source_w, source_h = ImageReader(str(path)).getSize()
    ratio = min(width / source_w, height / source_h)
    image = Image(str(path), width=source_w * ratio, height=source_h * ratio)
    image.hAlign = "CENTER"
    output = [image]
    if caption:
        output.append(p(caption, "CaptionBT"))
    return output


def bullet(items: list[str], color: colors.Color = GREEN) -> Table:
    rows = []
    for item in items:
        rows.append([
            Paragraph("●", ParagraphStyle("BulletDot", parent=styles["BodyBT"], textColor=color, fontName=FONT_BOLD)),
            p(item, "BodyBT"),
        ])
    table = Table(rows, colWidths=[7 * mm, 156 * mm], hAlign="LEFT")
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))
    return table


def callout(title: str, body: str, accent=YELLOW) -> Table:
    table = Table([[p(title, "CalloutBT")], [p(body, "BodyBT")]], colWidths=[164 * mm])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF9E7")),
        ("BOX", (0, 0), (-1, -1), 1, accent),
        ("LINEBEFORE", (0, 0), (0, -1), 4, accent),
        ("LEFTPADDING", (0, 0), (-1, -1), 12),
        ("RIGHTPADDING", (0, 0), (-1, -1), 12),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return table


def table(data: list[list[str]], widths: list[float], header=True) -> Table:
    converted = []
    for row_index, row in enumerate(data):
        style = "TableHeadBT" if header and row_index == 0 else "TableBT"
        converted.append([p(cell, style) for cell in row])
    t = Table(converted, colWidths=widths, repeatRows=1 if header else 0, hAlign="LEFT")
    commands = [
        ("GRID", (0, 0), (-1, -1), 0.45, LINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]
    if header:
        commands += [("BACKGROUND", (0, 0), (-1, 0), GREEN), ("TEXTCOLOR", (0, 0), (-1, 0), WHITE)]
        if len(data) > 1:
            commands.append(("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, colors.HexColor("#F1ECE0")]))
    t.setStyle(TableStyle(commands))
    return t


def page_background(canvas, doc):
    canvas.saveState()
    page = canvas.getPageNumber()
    width, height = A4
    if page == 1:
        canvas.setFillColor(GREEN_DARK)
        canvas.rect(0, 0, width, height, fill=1, stroke=0)
        canvas.setFillColor(colors.Color(1, 1, 1, alpha=0.06))
        for x, y, r in [(34 * mm, 245 * mm, 28 * mm), (180 * mm, 38 * mm, 40 * mm), (195 * mm, 265 * mm, 15 * mm)]:
            canvas.circle(x, y, r, fill=1, stroke=0)
    else:
        canvas.setFillColor(PAPER)
        canvas.rect(0, 0, width, height, fill=1, stroke=0)
        canvas.setStrokeColor(LINE)
        canvas.setLineWidth(0.6)
        canvas.line(18 * mm, 14 * mm, width - 18 * mm, 14 * mm)
        canvas.setFont(FONT, 7.8)
        canvas.setFillColor(MUTED)
        canvas.drawString(18 * mm, 8 * mm, "Better Together · 本地演示合成数据")
        canvas.drawRightString(width - 18 * mm, 8 * mm, f"{page:02d}")
    canvas.restoreState()


class DemoDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str):
        super().__init__(filename, pagesize=A4, leftMargin=23 * mm, rightMargin=23 * mm, topMargin=19 * mm, bottomMargin=22 * mm)
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="normal", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
        self.addPageTemplates([PageTemplate(id="main", frames=frame, onPage=page_background)])


def build_story():
    story = []
    # 1 Cover
    story += [Spacer(1, 42 * mm), p("PRODUCT DEMO GUIDE", "CoverKicker"), p("Better\nTogether", "CoverTitle"), p("有证据的坚持，也有人同行。", "CoverSub"), Spacer(1, 20 * mm), callout("本次演示看什么？", "从定计划到拍照打卡，从 AI 建议到分组确认，再到小队互动与周报复盘。所有示例均为本地合成数据。", YELLOW), Spacer(1, 22 * mm), rich("<font color='#DCE9DE'>iOS 模拟器演示版 · 2026</font>", "SmallBT"), PageBreak()]

    # 2 Product value
    story += [p("01 · 为什么是 Better Together", "H1BT"), p("把坚持变成一张看得见的收据。每个人有自己的目标，小队提供温和的可见性，让监督变成支持。", "BodyBT"), callout("核心闭环", "定计划 → 拍照或选图 → AI 提供归类建议 → 用户确认 → 盖章归档 → 队友看见 → 周报复盘", RED), Spacer(1, 8), table([
        ["用户动作", "产品回应", "现场可见结果"],
        ["我想开始一个目标", "计划支持固定星期、周期目标和间隔执行", "今天页出现清晰的下一步"],
        ["我想证明完成了", "照片、截图和逐图摘要形成证据", "提交后留下盖章记录"],
        ["我想有人陪着", "小队动态、点赞、评论、戳一下", "进度被看见但不公开排名"],
        ["我想知道这周怎样", "个人周报和小队周报", "一页看懂完成率与亮点"],
    ], [39 * mm, 61 * mm, 64 * mm]), Spacer(1, 10), p("产品边界", "H2BT"), bullet(["不做公开社区，不做排行榜，不以押金和惩罚驱动坚持。", "私密计划只属于本人；分享给小队的内容经过明确的可见范围控制。", "AI 是辅助建议，最终归属、摘要和字段由用户确认。"]), PageBreak()]

    # 3 Team
    story += [p("02 · 演示小队：把日子过好", "H1BT"), p("固定时区 Asia/Shanghai，5 位成员各自有计划，今天的状态刚好组成一张有起伏的团队快照。", "BodyBT"), Spacer(1, 5), table([
        ["成员", "今日状态", "讲解角色"],
        ["知夏", "进行中", "当前账号，演示建立计划和混合打卡"],
        ["小予", "已完成", "展示运动记录、点赞和评论"],
        ["陈一", "已完成", "展示学习记录与周报贡献"],
        ["林晓", "未开始", "展示逾期提醒和戳一下"],
        ["安然", "已补卡", "展示补卡后状态与连续记录"],
    ], [34 * mm, 31 * mm, 99 * mm]), Spacer(1, 12), p("小队状态矩阵", "H2BT"), table([
        ["可演示状态", "界面表达", "不混淆的业务语义"],
        ["进行中", "正在完成今天的计划", "不是失败，也不是逾期"],
        ["已完成", "已盖章", "可点赞、评论和查看摘要"],
        ["已补卡", "补卡标签", "补卡会保留历史痕迹"],
        ["未开始", "尚未提交", "仅在截止后才可能变成逾期动态"],
    ], [35 * mm, 49 * mm, 80 * mm]), Spacer(1, 12), callout("隐私提示", "这是本地演示小队，成员姓名、状态、照片和互动均为合成内容，不连接真实账号。", RED), PageBreak()]

    # 4 Plans
    story += [p("03 · 计划：不要求每个人用同一种节奏", "H1BT"), p("计划编辑器把“坚持”拆成更接近日常的规则。目标是可执行、可解释、可复盘。", "BodyBT"), Spacer(1, 4), table([
        ["计划", "频率", "可见范围", "本周讲解重点"],
        ["每天读 20 页", "固定星期", "小队可见", "今天到期、连续阅读"],
        ["出门走一走", "每隔 2 天", "小队可见", "按开始日固定排期"],
        ["喝水 3 天", "每 5 天完成 3 天", "小队可见", "周期目标与额外完成"],
        ["好好吃晚饭", "每天", "仅自己可见", "私密计划不进入小队统计"],
        ["十分钟冥想", "每周完成 3 天", "小队可见", "按周结算连续达标"],
    ], [39 * mm, 42 * mm, 34 * mm, 49 * mm]), Spacer(1, 12), p("统计口径", "H2BT"), bullet(["同一天多次记录只计一天，额外完成单独展示。", "周期目标按当地日历和小队固定时区结算，不因迟到打卡顺延。", "完成率最高显示 100%，超额天数另列，避免把鼓励变成虚假的百分比。"]), Spacer(1, 12)] + img("ios-flexible-interval-plan.png", 64 * mm, 86 * mm, "计划编辑器：周期和间隔规则在同一套界面中表达") + [PageBreak()]

    # 5 Check-in flow
    story += [p("04 · 打卡：先整理，再识别，再确认", "H1BT"), p("选图后不会立刻发起识别。用户可以先检查照片、删除不合格内容，再点击下一步让系统一次处理整批。", "BodyBT"), Spacer(1, 4)]
    flow_imgs = []
    for name, caption in [("ios-batch-classic-preview.png", "预览：增删照片"), ("ios-batch-classic-grouped.png", "分组：按计划拆条"), ("ios-batch-classic-edited.png", "确认：移动照片与改计划"), ("ios-batch-classic-stamped.png", "归档：提交后盖章")]:
        flow_imgs.append(img(name, 37 * mm, 77 * mm, caption))
    story.append(Table([[item[0] for item in flow_imgs]], colWidths=[40 * mm] * 4, hAlign="LEFT"))
    story.append(Spacer(1, 10))
    story.append(callout("混合照片会拆成多条记录", "学习照片进入学习记录，运动截图进入运动记录；每条记录保留自己的照片、字段和事实摘要。用户可以在确认页移动单张照片，也可以修改整条记录的计划。", YELLOW))
    story += [Spacer(1, 10), bullet(["原图只在最终确认后上传到私有存储。", "识别失败、超时或低置信度不会阻止盖章，照片进入 ALL 或待补状态。", "重复点击确认使用幂等键，不创建重复记录。"]), PageBreak()]

    # 6 AI and memo
    story += [p("05 · AI：给建议，不替用户做决定", "H1BT"), p("Better Together 的识别结果是可检查、可编辑的事实草稿。每张图片都有独立摘要，摘要与最终计划归属分开保存。", "BodyBT"), Spacer(1, 4), table([
        ["规则", "演示中的表现"],
        ["置信度至少 80%", "才参与自动归类；低于阈值保留 ALL"],
        ["严格过半投票", "多图有明确多数才归入一个计划；平票仍为 ALL"],
        ["用户手动选择优先", "手动调整后，迟到的 AI 结果不能覆盖"],
        ["运动数据有来源", "时长、距离、热量只来自截图或已有数据"],
        ["饮食热量是估算", "字段明确显示“估算”，不冒充精确测量"],
    ], [55 * mm, 109 * mm]), Spacer(1, 12), p("纪要示例", "H2BT"), callout("学习记录", "完成《也许你该找个人聊聊》两章，记下“改变往往从认真倾听开始”。", GREEN), Spacer(1, 7), callout("运动记录", "沿河边步行 32 分钟。截图读到时长，其他未记录字段保持未记录。", RED), Spacer(1, 7), callout("饮食记录", "晚餐包含蔬菜、米饭和鸡蛋。热量显示估算区间，并标记来源。", YELLOW), Spacer(1, 10), p("演示中的 AI 返回值是测试夹具，不代表真实模型准确率或供应商性能。", "SmallBT"), PageBreak()]

    # 7 Interactions
    story += [p("06 · 小队互动：看见进度，也保留边界", "H1BT"), p("动态流把不同业务状态分开表达，避免把普通鼓励、逾期提醒和质疑流程混成同一种卡片。", "BodyBT"), Spacer(1, 5), table([
        ["动态类型", "可以做什么", "不能做什么"],
        ["盖章卡", "点赞、评论、提出质疑", "不能把未过半质疑直接改成失败"],
        ["逾期动态", "戳一下", "不能点赞、评论或发送鼓励"],
        ["周报卡", "点赞、评论、分享", "不能查看队友私密计划明细"],
    ], [36 * mm, 65 * mm, 63 * mm]), Spacer(1, 12), p("现场可演示的三种质疑结果", "H2BT"), bullet(["1/3：质疑未过半，记录保持已盖章。", "2/3：质疑过半，记录变为待重打，次日 12:00 前可处理。", "用户本人不能质疑自己，每人每天有质疑上限，所有动作保留痕迹。"]), Spacer(1, 12), callout("演示提醒", "林晓的逾期卡只出现“戳一下”；小予的正常盖章卡才出现点赞和评论入口。", RED), PageBreak()]

    # 8 Reports
    story += [p("07 · 周报：把一周收成一页", "H1BT"), p("周报把计划完成、补卡、连续变化、纪要精选和下周建议放在同一份可分享的收据里。", "BodyBT"), Spacer(1, 5)] + img("ios-report-light.png", 79 * mm, 104 * mm, "个人周报：只展示本人的数据") + [Spacer(1, 8), table([
        ["模块", "演示数据"],
        ["完成情况", "11 / 14，完成率 79%"],
        ["分类汇总", "学习 7 次，运动 4 次，饮食不计入小队公开统计"],
        ["亮点", "留下阅读笔记、走出家门、调整更适合自己的时段"],
        ["下周建议", "给晚饭计划留一个更宽松的截止时间"],
    ], [38 * mm, 126 * mm]), Spacer(1, 8), callout("两个分享动作", "发送到小队动态，或保存只含本人数据的长图。分享动作会记录状态，重新生成不会复制出第二条周报。", YELLOW), PageBreak()]

    # 9 Appearance
    story += [p("08 · 两套外观，同一套产品语义", "H1BT"), p("经典纸面强调收据、章印和信息层级；团团陪你用更轻的插画表达陪伴。两套外观共享相同的业务状态和操作顺序。", "BodyBT"), Spacer(1, 4)]
    appearance = Table([[img("ios-today-light.png", 63 * mm, 101 * mm, "经典纸面"), img("ios-appearance-tuantuan-today-light.png", 63 * mm, 101 * mm, "团团陪你")]], colWidths=[80 * mm, 80 * mm], hAlign="LEFT")
    story += [appearance, Spacer(1, 8), p("平台体验检查点", "H2BT"), bullet(["iOS 使用安全区、系统返回手势和动态字体；触控目标至少 44pt。", "深色模式、加载态、失败态和键盘遮挡有独立处理。", "图片支持点击全屏、双指缩放、双击放大和左右切换。", "演示以 iOS Simulator 为主，真机和 Android 使用同一业务模型。"]), Spacer(1, 8)] + img("ios-settings-large-dark.png", 59 * mm, 54 * mm, "大字号深色设置页：状态仍可扫描") + [PageBreak()]

    # 10 Script and boundaries
    story += [p("09 · 8 分钟现场讲解脚本", "H1BT"), table([
        ["时间", "操作", "讲解重点"],
        ["0:00–1:00", "打开今日页", "5 人状态、共同连续天数、今日计划"],
        ["1:00–2:00", "打开计划页", "固定星期、周期目标、间隔执行"],
        ["2:00–4:00", "进入打卡，选 3 张照片", "预览不识别，下一步才处理整批"],
        ["4:00–5:30", "分组确认页移动照片", "学习和运动拆条，用户拥有最终决定权"],
        ["5:30–6:30", "确认并查看动态", "盖章、点赞评论、逾期戳一下的差异"],
        ["6:30–7:30", "打开周报", "完成率、亮点、建议、分享"],
        ["7:30–8:00", "切换外观与设置", "双外观、通知、AI BYOK 和隐私边界"],
    ], [30 * mm, 61 * mm, 73 * mm]), Spacer(1, 12), p("演示边界和后续", "H2BT"), bullet(["本套数据和图片是本地演示合成数据，不代表真实用户行为。", "正式账号使用 Supabase 私有存储和 RLS；BYOK 密钥只保存在设备安全存储。", "演示模式不发送照片到 AI 服务，也不验证真实模型准确率。", "后续可接入真实小队、真实邀请、真实供应商和正式通知通道。"]), Spacer(1, 12), callout("一句话收尾", "Better Together 不替你完成目标，它让今天做过的事留下证据，也让同行的人知道你还在坚持。", RED), Spacer(1, 16), p("文档版本：本地演示场景 showcase_v2 · 2026", "SmallBT")]
    return story


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    TMP.mkdir(parents=True, exist_ok=True)
    doc = DemoDocTemplate(str(OUT))
    doc.build(build_story())
    print(OUT)


if __name__ == "__main__":
    main()
