#!/usr/bin/env python3
"""Generates the architecture diagram in three formats from one layout definition.

    python3 docs/generate_diagram.py

Outputs (next to this script):
    architecture.drawio   editable in https://app.diagrams.net (uses AWS icons)
    architecture.png      embedded in the README
    architecture.svg      vector copy
"""
from pathlib import Path
from xml.sax.saxutils import escape

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

OUT = Path(__file__).parent
W, H = 1800, 1060

# AWS category colours
ORANGE, PURPLE, GREEN, MAGENTA, RED, PINK, GREY = (
    "#ED7100", "#8C4FFF", "#7AA116", "#C925D1", "#DD344C", "#E7157B", "#5A6B7B",
)

# ---------------------------------------------------------------- groups
# (id, x, y, w, h, title, colour, dashed)
GROUPS = [
    ("cloud", 180, 20, 1600, 1020, "AWS Cloud", "#232F3E", False),
    ("region", 400, 60, 1360, 960, "Region: us-east-1", "#00A4A6", True),
    ("vpc", 430, 100, 1090, 900, "VPC 10.0.0.0/16", PURPLE, False),
    ("az_a", 460, 140, 510, 840, "Availability Zone A", "#7D8998", True),
    ("az_b", 990, 140, 510, 840, "Availability Zone B", "#7D8998", True),
    ("pub_a", 480, 170, 470, 190, "Public subnet 10.0.0.0/24", GREEN, False),
    ("pub_b", 1010, 170, 470, 190, "Public subnet 10.0.1.0/24", GREEN, False),
    ("priv_a", 480, 390, 470, 250, "Private subnet 10.0.10.0/24", "#147EBA", False),
    ("priv_b", 1010, 390, 470, 250, "Private subnet 10.0.11.0/24", "#147EBA", False),
    ("data_a", 480, 670, 470, 280, "Data subnet 10.0.20.0/24 (no internet route)", "#B0084D", False),
    ("data_b", 1010, 670, 470, 280, "Data subnet 10.0.21.0/24 (no internet route)", "#B0084D", False),
    ("asg", 475, 415, 995, 210, "ASG min 2, max 4, CPU target 50%", ORANGE, True),
]

# Where a group's title sits: default top-left; "tr" top-right; "bl" bottom-left.
TITLE_POS = {"az_a": "tr", "az_b": "tr", "asg": "bl"}

# ---------------------------------------------------------------- nodes
# (id, x, y, w, h, label, colour, icon or None, dashed)
NODES = [
    ("users", 20, 205, 130, 70, "Internet users", GREY, None, False),
    ("admin", 20, 520, 130, 70, "Engineer", GREY, None, False),
    ("r53", 210, 90, 150, 75, "Route 53\nAlias A to ALB\nHTTP health check", PURPLE, "route_53", False),
    ("cf", 210, 205, 150, 85, "CloudFront\n/static/* cached\nHTTPS for viewers", PURPLE, "cloudfront", False),
    ("ssm", 210, 520, 150, 85, "Systems Manager\nSession Manager\n(no SSH, no bastion)", PINK, "systems_manager", False),
    ("igw", 392, 205, 76, 50, "Internet\nGateway", PURPLE, None, False),
    ("waf", 525, 205, 95, 50, "AWS WAF\nOWASP rules", RED, "waf", False),
    ("alb", 640, 200, 720, 60, "Application Load Balancer\nHTTP :80, health check /health, path rules", PURPLE, "elastic_load_balancing", False),
    ("nat_a", 520, 285, 160, 60, "NAT Gateway\n(Elastic IP)", PURPLE, None, False),
    ("nat_b", 1040, 285, 160, 60, "NAT Gateway #2\n(optional)", PURPLE, None, True),
    ("ec2_a", 520, 475, 380, 110, "EC2 t3.micro, AL2023\nGunicorn + Flask :8000\nIMDSv2, SSM agent, no SSH", ORANGE, "ec2", False),
    ("ec2_b", 1040, 475, 380, 110, "EC2 t3.micro, AL2023\nGunicorn + Flask :8000\nIMDSv2, SSM agent, no SSH", ORANGE, "ec2", False),
    ("rds_a", 560, 715, 300, 110, "RDS PostgreSQL\nPRIMARY (db.t3.micro)\nencrypted, Multi-AZ", MAGENTA, "rds", False),
    ("rds_b", 1090, 715, 300, 110, "RDS PostgreSQL\nSTANDBY\nautomatic failover", MAGENTA, "rds", False),
    ("vpce", 1478, 430, 84, 50, "S3 gateway\nendpoint", PURPLE, None, False),
    ("s3", 1580, 420, 160, 90, "S3 bucket\napp bundle", GREEN, "s3", False),
    ("secrets", 1580, 540, 160, 90, "Secrets Manager\nRDS-managed\ncredentials", RED, "secrets_manager", False),
    ("cw", 1580, 690, 160, 100, "CloudWatch\ndashboard + alarms\n(ALB, ASG, RDS, WAF)", PINK, "cloudwatch", False),
    ("sns", 1580, 830, 160, 80, "SNS\nemail alerts", PINK, "sns", False),
]

# ---------------------------------------------------------------- edges
# (x1, y1, x2, y2, label, dashed, colour, both_ways, label_dx, label_dy)
EDGES = [
    (150, 232, 210, 240, "1", False, "#232F3E", False, -2, -14),
    (120, 205, 210, 135, "DNS", True, "#7D8998", False, -18, -4),
    (360, 115, 900, 200, "alias", True, "#7D8998", False, -235, -36),
    (360, 247, 392, 232, "2", False, "#232F3E", False, 0, -12),
    (468, 230, 525, 230, "", False, "#232F3E", False, 0, 0),
    (620, 230, 640, 230, "", False, "#232F3E", False, 0, 0),
    (800, 260, 710, 475, "3  HTTP :8000", False, "#232F3E", False, 0, 0),
    (1200, 260, 1230, 475, "3  HTTP :8000", False, "#232F3E", False, 0, 0),
    (710, 585, 710, 715, "4  PostgreSQL :5432 (TLS)", False, "#232F3E", False, 0, 0),
    (1180, 585, 860, 745, "4", False, "#232F3E", False, 0, -10),
    (860, 770, 1090, 770, "5  synchronous replication", False, "#B0084D", True, 0, -12),
    (672, 475, 672, 345, "outbound via NAT", True, "#7D8998", False, 0, 38),
    (520, 315, 430, 255, "", True, "#7D8998", False, 0, 0),
    (1420, 500, 1478, 462, "", False, "#232F3E", False, 0, 0),
    (1562, 455, 1580, 455, "", False, "#232F3E", False, 0, 0),
    (1470, 590, 1580, 585, "via NAT", True, "#7D8998", False, -2, -12),
    (360, 562, 475, 530, "6  Session Manager", True, "#E7157B", False, -4, 22),
    (150, 556, 210, 562, "", False, "#232F3E", False, 0, 0),
    (1580, 740, 1470, 600, "alarms trigger scaling", True, "#E7157B", False, -22, 12),
    (1660, 790, 1660, 830, "", False, "#232F3E", False, 0, 0),
]

NOTES = [
    (1215, 286, "Default: one NAT (cheap).\nsingle_nat_gateway = false\nadds one per AZ.", "#5A6B7B", 230, 52),
    (480, 958, "Security groups: ALB -> app :8000 -> database :5432. Custom NACLs on all three tiers.", "#5A6B7B", 700, 20),
]


def render_png_svg() -> None:
    fig = plt.figure(figsize=(W / 100, H / 100), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")

    for _id, x, y, w, h, title, colour, dashed in GROUPS:
        ax.add_patch(Rectangle((x, y), w, h, fill=False, ec=colour, lw=1.8, ls=(0, (5, 4)) if dashed else "-"))
        pos = TITLE_POS.get(_id, "tl")
        tx, ty, ha, va = {
            "tl": (x + 8, y + 6, "left", "top"),
            "tr": (x + w - 8, y + 6, "right", "top"),
            "bl": (x + 8, y + h - 6, "left", "bottom"),
        }[pos]
        ax.text(tx, ty, title, ha=ha, va=va, fontsize=9.5, color=colour, fontweight="bold")

    for _id, x, y, w, h, label, colour, _icon, dashed in NODES:
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size=6", fc="white", ec=colour, lw=2, ls=(0, (4, 3)) if dashed else "-"))
        ax.add_patch(Rectangle((x, y), 9, h, fc=colour, ec="none"))
        ax.text(x + 9 + (w - 9) / 2, y + h / 2, label, ha="center", va="center", fontsize=9, color="#16191f", linespacing=1.35)

    for x1, y1, x2, y2, label, dashed, colour, both, dx, dy in EDGES:
        style = "<|-|>" if both else "-|>"
        ax.annotate(
            "", xy=(x2, y2), xytext=(x1, y1),
            arrowprops=dict(arrowstyle=style, color=colour, lw=1.7, ls=(0, (4, 3)) if dashed else "-", shrinkA=0, shrinkB=0, mutation_scale=13),
        )
        if label:
            ax.text((x1 + x2) / 2 + dx, (y1 + y2) / 2 + dy, label, ha="center", va="center", fontsize=8.5, color=colour,
                    fontweight="bold", bbox=dict(fc="white", ec="none", pad=1.2, alpha=0.92))

    for x, y, text, colour, _w, _h in NOTES:
        ax.text(x, y, text, ha="left", va="top", fontsize=8.5, color=colour, style="italic")

    fig.savefig(OUT / "architecture.png", dpi=100)
    fig.savefig(OUT / "architecture.svg")
    plt.close(fig)


def render_drawio() -> None:
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    n = [1]

    def nid() -> str:
        n[0] += 1
        return f"c{n[0]}"

    for gid, x, y, w, h, title, colour, dashed in GROUPS:
        style = (f"rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor={colour};fontColor={colour};"
                 f"fontStyle=1;fontSize=11;strokeWidth=2;"
                 + {"tl": "verticalAlign=top;align=left;spacingLeft=8;spacingTop=2;",
                    "tr": "verticalAlign=top;align=right;spacingRight=8;spacingTop=2;",
                    "bl": "verticalAlign=bottom;align=left;spacingLeft=8;spacingBottom=2;"}[TITLE_POS.get(gid, "tl")]
                 + ("dashed=1;" if dashed else ""))
        cells.append(f'<mxCell id="{gid}" value="{escape(title)}" style="{style}" vertex="1" parent="1">'
                     f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')

    for nid_, x, y, w, h, label, colour, icon, dashed in NODES:
        # draw.io stores HTML labels entity-encoded inside the attribute, so <br> becomes &lt;br&gt;
        text = escape(label, {'"': "&quot;"}).replace("\n", "&lt;br&gt;")
        pad = 46 if icon else 8
        style = (f"rounded=1;arcSize=6;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor={colour};strokeWidth=2;"
                 f"fontColor=#16191f;fontSize=11;align={'left' if icon else 'center'};spacingLeft={pad};verticalAlign=middle;"
                 + ("dashed=1;" if dashed else ""))
        cells.append(f'<mxCell id="{nid_}" value="{text}" style="{style}" vertex="1" parent="1">'
                     f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        if icon:
            istyle = (f"sketch=0;outlineConnect=0;fontColor=#232F3E;fillColor={colour};strokeColor=#ffffff;dashed=0;"
                      f"verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;aspect=fixed;"
                      f"shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon};")
            cells.append(f'<mxCell id="{nid_}_icon" value="" style="{istyle}" vertex="1" parent="1">'
                         f'<mxGeometry x="{x + 7}" y="{y + (h - 34) / 2}" width="34" height="34" as="geometry"/></mxCell>')

    for x1, y1, x2, y2, label, dashed, colour, both, _dx, _dy in EDGES:
        style = (f"endArrow=block;startArrow={'block' if both else 'none'};html=1;strokeColor={colour};strokeWidth=2;"
                 f"fontColor={colour};fontStyle=1;fontSize=10;labelBackgroundColor=#ffffff;" + ("dashed=1;" if dashed else ""))
        cells.append(f'<mxCell id="{nid()}" value="{escape(label)}" style="{style}" edge="1" parent="1">'
                     f'<mxGeometry relative="1" as="geometry"><mxPoint x="{x1}" y="{y1}" as="sourcePoint"/>'
                     f'<mxPoint x="{x2}" y="{y2}" as="targetPoint"/></mxGeometry></mxCell>')

    for x, y, text, colour, nw, nh in NOTES:
        style = f"text;html=1;align=left;verticalAlign=top;fontColor={colour};fontStyle=2;fontSize=10;"
        value = escape(text).replace("\n", "&lt;br&gt;")
        cells.append(f'<mxCell id="{nid()}" value="{value}" style="{style}" vertex="1" parent="1">'
                     f'<mxGeometry x="{x}" y="{y}" width="{nw}" height="{nh}" as="geometry"/></mxCell>')

    xml = (f'<mxfile host="app.diagrams.net"><diagram id="arch" name="Architecture">'
           f'<mxGraphModel dx="{W}" dy="{H}" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
           f'fold="1" page="1" pageScale="1" pageWidth="{W}" pageHeight="{H}" math="0" shadow="0"><root>'
           + "".join(cells) + "</root></mxGraphModel></diagram></mxfile>")
    (OUT / "architecture.drawio").write_text(xml, encoding="utf-8")


if __name__ == "__main__":
    render_png_svg()
    render_drawio()
    print("wrote architecture.png, architecture.svg, architecture.drawio in", OUT)
