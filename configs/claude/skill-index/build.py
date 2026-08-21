#!/usr/bin/env python3
"""Regenerate skill-index/SKILL.md from the skill tree under ~/.claude/skills.

Claude Code only auto-discovers skills at ~/.claude/skills/<name>/SKILL.md — one
level deep. Everything nested under a category directory is invisible to the
harness, so this index is what makes those skills reachable: it is itself a flat
skill, and its body tells Claude which nested SKILL.md to read on demand.

Usage:  python3 ~/.claude/skills/skill-index/build.py
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path.home() / ".claude" / "skills"
SELF = "skill-index"
TRIGGERS = ROOT / SELF / "triggers.json"
OUT = ROOT / SELF / "SKILL.md"

# Category display order and heading.
CATEGORIES = {
    "callabo": "Callabo 서비스",
    "integration": "외부 서비스 연동",
    "integrations": "외부 서비스 연동 (구)",
    "pronaia": "Pronaia / ML",
    "agents": "에이전트 워크플로우",
    "common": "공용",
    "context": "컨텍스트",
    "development": "개발",
}

FRONTMATTER_KEY = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$")

# Snapshot directories left behind by syncs (foo.backup.20260811101821, foo.bak).
# They carry the same frontmatter `name` as the live skill, so cataloguing them
# emits duplicate rows pointing at stale copies.
ARCHIVED_DIR = re.compile(r"\.(backup|bak|old|orig)(\.|$)")


def read_frontmatter(md: pathlib.Path) -> dict[str, str]:
    lines = md.read_text(errors="replace").splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    end = next((i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"), None)
    if end is None:
        return {}
    fields: dict[str, str] = {}
    cur = None
    for line in lines[1:end]:
        m = FRONTMATTER_KEY.match(line)
        if m:
            cur = m.group(1)
            fields[cur] = (m.group(2) or "").strip()
        elif cur and (line.startswith((" ", "\t")) or not line.strip()):
            fields[cur] = f"{fields[cur]} {line.strip()}".strip()
    # Drop YAML block-scalar indicators (|, >, |-, >-) so they don't leak into the table.
    return {
        k: re.sub(r"\s+", " ", re.sub(r"^[|>][+-]?\s*", "", v)).strip()
        for k, v in fields.items()
    }


def autoloaded_names() -> set[str]:
    """Skill names the harness already discovers at ~/.claude/skills/<name>/SKILL.md.

    Cataloguing these again costs context in every session that reads this index
    while telling Claude nothing it cannot already see.
    """
    names = set()
    for entry in os.listdir(ROOT):
        md = ROOT / entry / "SKILL.md"
        if md.exists():
            names.add(read_frontmatter(md).get("name", entry))
    return names


def collect() -> list[dict]:
    found = []
    autoloaded = autoloaded_names()
    for cat in sorted(os.listdir(ROOT)):
        cat_path = ROOT / cat
        if not cat_path.is_dir() or cat == SELF:
            continue
        if (cat_path / "SKILL.md").exists():
            continue  # flat skill — the harness already loads it
        for entry in sorted(os.listdir(cat_path)):
            md = cat_path / entry / "SKILL.md"
            if not md.exists() or ARCHIVED_DIR.search(entry):
                continue
            fm = read_frontmatter(md)
            if fm.get("name", entry) in autoloaded:
                continue  # promoted to depth 1 already; this copy is redundant
            found.append(
                {
                    "name": fm.get("name", entry),
                    "dir": entry,
                    "category": cat,
                    "path": f"~/.claude/skills/{cat}/{entry}/SKILL.md",
                    "desc": fm.get("description", ""),
                    "symlink": (cat_path / entry).is_symlink(),
                }
            )
    return found


def main() -> None:
    skills = collect()
    triggers = json.loads(TRIGGERS.read_text()) if TRIGGERS.exists() else {}

    # The table prints frontmatter `name` and the body tells the reader to assemble
    # the path from it, so a directory whose name differs makes the catalogued path
    # wrong. This held only by convention until two entries quietly broke it
    # (static-index/indexing-static-context, grill-me/grilling-plans); verify it.
    for s in skills:
        if s["name"] != s["dir"]:
            print(
                f"WARNING: {s['category']}/{s['dir']} declares name '{s['name']}' — "
                "the catalogued path will not resolve. Rename one to match.",
                file=sys.stderr,
            )

    by_cat: dict[str, list[dict]] = {}
    for s in skills:
        by_cat.setdefault(s["category"], []).append(s)

    order = [c for c in CATEGORIES if c in by_cat] + sorted(set(by_cat) - set(CATEGORIES))

    head_terms = ", ".join(
        sorted({s["name"] for s in skills if s["category"] in ("callabo", "integration")})
    )

    body = [
        "---",
        "name: skill-index",
        "description: >-",
        "  Catalog of the nested skills under ~/.claude/skills that Claude Code does not",
        "  auto-discover (they live one directory deeper than the harness scans). Load this",
        "  whenever a task touches Callabo (auth, mongodb, notion, slack, records, insights,",
        "  labels, amplitude, metabase, blog, image, voiceprint, speaker, transcription,",
        "  member matching, poc analytics, competitor analysis, crm, product info, workspace",
        "  health/audit, resolve, callabo-set), an integration (kibana/로그, linear/이슈,",
        "  notion/노션, sentry/에러), Pronaia ML work (audio, triton, model sync, benchmark),",
        "  or managing services and Obsidian notes — or whenever the user asks what skills",
        "  exist. It maps each skill to its SKILL.md path so the right one can be read on",
        "  demand instead of loading all of them every session. Skills that already load at",
        "  depth 1 (korean-editor, rpf, grill-me, static-index, context-manager,",
        "  git-commit-pr, security-auditor, background-*) are NOT listed here — the harness",
        "  already surfaces them, so do not read this index looking for those.",
        "---",
        "",
        "# Skill Index",
        "",
        f"`~/.claude/skills` 아래 **{len(skills)}개** 스킬이 카테고리 디렉토리 안에 있습니다.",
        "Claude Code는 `~/.claude/skills/<이름>/SKILL.md` **한 depth만** 스캔하므로 이 스킬들은",
        "자동 로딩되지 않습니다. 대신 이 인덱스를 통해 필요할 때만 꺼내 씁니다.",
        "",
        "## 사용법",
        "",
        "1. 아래 표에서 작업에 맞는 스킬을 찾는다.",
        "2. 해당 `SKILL.md`를 **Read** 한다.",
        "3. 그 내용을 정식으로 호출된 스킬처럼 그대로 따른다 (스크립트 경로·환경변수 포함).",
        "",
        "디렉토리명 == frontmatter `name` 이 항상 성립하므로, 경로는",
        "`~/.claude/skills/<카테고리>/<이름>/SKILL.md` 로 바로 조립할 수 있습니다.",
        "",
        "> `~/.agents/*.md` 는 별개입니다 — SessionStart 훅이 실제로 존재하는 파일만 골라",
        "> 트리거와 함께 요약해 주입하므로, 파일명을 여기서 추측하지 말고 그 요약을 보세요.",
        "> 스크립트 래퍼와 상세 절차가 필요할 때 아래 `integration-*` 스킬을 읽으세요.",
        "",
    ]

    for cat in order:
        body.append(f"## {cat} — {CATEGORIES.get(cat, cat)}")
        body.append("")
        body.append("| 스킬 | 트리거 | 설명 |")
        body.append("|---|---|---|")
        for s in sorted(by_cat[cat], key=lambda x: x["name"]):
            trig = triggers.get(s["name"], "")
            desc = s["desc"]
            if len(desc) > 190:
                desc = desc[:187].rstrip() + "…"
            desc = desc.replace("|", "\\|")
            trig = trig.replace("|", "\\|")
            mark = " ↗" if s["symlink"] else ""
            body.append(f"| `{s['name']}`{mark} | {trig} | {desc} |")
        body.append("")

    body += [
        "↗ = 소스 레포(`~/workspace/agents`, `~/personal/agent-skills`)로의 심볼릭 링크.",
        "내용을 고치면 레포가 수정되니 커밋 여부를 확인하세요.",
        "",
        "## 유지보수",
        "",
        "스킬을 추가·삭제한 뒤에는 인덱스를 재생성합니다:",
        "",
        "```bash",
        "python3 ~/.claude/skills/skill-index/build.py",
        "```",
        "",
        "규칙: 새 스킬의 디렉토리명은 frontmatter `name` 과 **정확히 일치**해야 하고,",
        "frontmatter 키는 `name`, `description`, `allowed-tools`, `license`, `metadata` 만",
        "허용됩니다 (`trigger-keywords`, `tags`, `priority` 는 스펙 외 — 트리거는",
        "`triggers.json` 또는 `description` 에 넣으세요).",
        "",
    ]

    OUT.write_text("\n".join(body))
    print(f"wrote {OUT} — {len(skills)} skills across {len(order)} categories")


if __name__ == "__main__":
    main()
