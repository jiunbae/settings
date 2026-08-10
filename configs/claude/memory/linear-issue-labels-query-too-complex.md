---
name: linear-issue-labels-query-too-complex
description: "linear-issue.sh --labels used to fail with \"Query too complex\"; fixed as of 2026-08-05 — use the helper, fall back to lean GraphQL labelIds only if it returns."
metadata:
  node_type: memory
  type: project
  originSessionId: 3934318d-55e9-4d62-a0ec-6dbcd6bad8c1
  modified: 2026-08-05T01:18:46.964Z
---

**Resolved as of 2026-08-05.** `linear-issue.sh update <ID> --labels "T: Bug,C: Server(API,Scheduler),E: Production,Created By Agent,W: Agent,Agent's Estimate" --execute` now succeeds against CAL and merges all six labels correctly (comma-containing names included). Use the helper first.

Historically (2026-07-27) it failed with HTTP 400 `Query too complex. Complexity: 24855. Maximum allowed complexity: 10000.` from the script's team-label *lookup* query, independent of label count.

**Why:** kept as a record so the old failure isn't re-diagnosed from scratch — if `Query too complex` reappears after a CAL label-tree change, it is the lookup query, not the mutation, and splitting labels across calls will not help.

**How to apply:** helper first. Only on a `Query too complex` response, resolve IDs yourself and call `issueUpdate(labelIds:)` (replaces the full set, so include every label to keep):

```bash
curl -s -X POST https://api.linear.app/graphql -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query($t:String!){team(id:$t){labels(first:250){nodes{id name parent{name}}}}}","variables":{"t":"fe1b5ce9-3e05-42fb-afa9-85527221f01e"}}'
```

Verifying with `linear-issue.sh get <ID> --json` no longer works — see [[linear-issue-get-identifier-broken]]. Needs [[agent-shell-missing-api-keys]] sourced first.
