---
name: linear-issue-get-identifier-broken
description: "linear-issue.sh get <TEAM>-123 by identifier broke on 2026-08-05 (issueSearch deprecated) but is fixed — use the helper; raw GraphQL only if it regresses."
metadata:
  node_type: memory
  type: reference
  modified: 2026-08-05T06:58:21.652Z
---

Earlier on 2026-08-05, `linear-issue.sh get <TEAM>-123 --json` returned `이슈를 찾을 수 없습니다` for issues that
definitely exist, because Linear deprecated the `issueSearch` endpoint the helper used
(`{"message":"deprecated","path":["issueSearch"],"code":"INPUT_ERROR"}`). **Verified fixed later the same day** —
`linear-issue.sh get <ISSUE-ID> --json` now returns the full issue normally.

Use the helper first. If identifier lookup ever misses again, do **not** conclude the issue is absent — fall back to raw GraphQL:

```bash
curl -s -X POST https://api.linear.app/graphql -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query { issue(id: \"<UUID>\") { identifier title state { name } labels { nodes { name } } } }"}'
# by number when you only have the identifier:
#   issues(filter: { team: { key: { eq: "<TEAM_KEY>" } }, number: { in: [<NUMBER>] } })
```

`linear-issue.sh update / comment / attach` were never affected. Same family of helper breakage as
[[linear-issue-labels-query-too-complex]]; remember to source `~/.envs/linear.env` first
([[agent-shell-missing-api-keys]]).
