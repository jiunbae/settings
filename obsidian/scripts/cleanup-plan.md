# Vault Cleanup Plan

## Rules Applied
- `~/workspace/{project}/` → `workspace/{project}/`
- `~/workspace-vibe/{service}/` → `workspace-vibe/{service}/`
- `~/workspace-ext/{project}/` → `workspace-ext/{project}/`
- Subfolders like `ssudam/server` should NOT create `ssudam-server`, they should merge into `ssudam`

---

## 1. ext-* folders → workspace-ext/

| Source | Action | Target |
|--------|--------|--------|
| `workspace/ext/` | DELETE | (root sessions, not needed) |
| `workspace/ext-clawdbot/` | MERGE | `workspace-ext/clawdbot/` |
| `workspace/ext-vision-insight-api/` | MERGE | `workspace-ext/vision-insight-api/` |

---

## 2. ssudam-* folders → ssudam/

| Source | Action | Target |
|--------|--------|--------|
| `workspace/ssudam-amoremall/` | MERGE | `workspace/ssudam/` |
| `workspace/ssudam-autocomplete/` | MERGE | `workspace/ssudam/` |
| `workspace/ssudam-calendar/` | MERGE | `workspace/ssudam/` |
| `workspace/ssudam-landing/` | MERGE | `workspace/ssudam/` |
| `workspace/ssudam-oliveyoung/` | MERGE | `workspace/ssudam/` |
| `workspace/ssudam-ssudam-server/` | MERGE | `workspace/ssudam/` |

---

## 3. proposal-* folders → proposal/

| Source | Action | Target |
|--------|--------|--------|
| `workspace/proposal-2025-12-3d-crack/` | MERGE | `workspace/proposal/` |
| `workspace/proposal-2025-12-llm-web3/` | MERGE | `workspace/proposal/` |
| `workspace/proposal-2025-12-trash-classification/` | MERGE | `workspace/proposal/` |

---

## 4. calex-* folders → calex/

| Source | Action | Target |
|--------|--------|--------|
| `workspace/calex-apps-server/` | MERGE | `workspace/calex/` |
| `workspace/calex-auth-ui/` | MERGE | `workspace/calex/` |
| `workspace/calex-server/` | MERGE | `workspace/calex/` |

---

## 5. Other merges

| Source | Action | Target |
|--------|--------|--------|
| `workspace/agent-skills-context/` | MERGE | `workspace/agent-skills/` |
| `workspace/OTPWidget-apple/` | MERGE | `workspace/OTPWidget/` |

---

## 6. Invalid folder names (starts with dash)

| Source | Action | Reason |
|--------|--------|--------|
| `workspace/-claude-plugins/` | DELETE | Invalid project path |
| `workspace/-config-opencode/` | DELETE | Invalid project path |
| `workspace/-ssh/` | DELETE | Invalid project path |

---

## 7. Weird/invalid folders

| Source | Action | Reason |
|--------|--------|--------|
| `workspace/Downloads-6-Subway-6-Subway/` | DELETE | Invalid path artifact |
| `workspace/Library-Mobile-Documents-...` | DELETE | iCloud path artifact |
| `workspace/workspace/` | DELETE | Nested workspace |
| `workspace/workspace-vibe/` | DELETE | Wrong location |

---

## 8. Root-level files to organize

| File | Action | Target |
|------|--------|--------|
| `workspace/이름 없는 보드.md` | MOVE | `workspace/_misc/` or DELETE |
| `workspace/TaskManage.md` | MOVE | `workspace/_misc/` or DELETE |

---

## Summary

| Action | Count |
|--------|-------|
| MERGE | 16 folders |
| DELETE | 10 folders |
| MOVE | 2 files |

**Total: 28 items to clean up**

---

## Execute with

```bash
python3 ~/s-lastorder/scripts/vault-cleanup.py --dry-run  # Preview
python3 ~/s-lastorder/scripts/vault-cleanup.py            # Execute
```
