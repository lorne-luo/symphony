---
name: jira
description: |
  Use Jira's REST API to read issues, post comments, transition states,
  and search with JQL during Symphony app-server sessions.
---

# Jira REST API

Use this skill for Jira operations during Symphony app-server sessions.

## Environment variables

All requests use these three variables:

| Variable        | Purpose                                     |
|-----------------|---------------------------------------------|
| `$JIRA_EMAIL`   | Atlassian account email                     |
| `$JIRA_API_KEY` | Atlassian API token (not your password)     |
| `$JIRA_ENDPOINT`| Base URL, e.g. `https://your-org.atlassian.net` |

All `curl` calls use HTTP Basic auth: `-u $JIRA_EMAIL:$JIRA_API_KEY`.

## Common operations

### View an issue

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_KEY" \
  -H "Accept: application/json" \
  "$JIRA_ENDPOINT/rest/api/3/issue/SYM-1"
```

Useful fields in the response: `key`, `fields.summary`, `fields.status.name`,
`fields.assignee.accountId`, `fields.description`.

### Add a comment

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_KEY" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"body": "comment text here"}' \
  "$JIRA_ENDPOINT/rest/api/3/issue/SYM-1/comment"
```

### Transition an issue (change status)

Transitions require two steps: discover available transitions, then apply one.

**Step 1 — list available transitions:**

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_KEY" \
  -H "Accept: application/json" \
  "$JIRA_ENDPOINT/rest/api/3/issue/SYM-1/transitions"
```

The response contains a `transitions` array. Find the object whose
`to.name` matches the desired status and note its `id`.

**Step 2 — apply the transition:**

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_KEY" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "31"}}' \
  "$JIRA_ENDPOINT/rest/api/3/issue/SYM-1/transitions"
```

Replace `"31"` with the `id` from Step 1.

### Search with JQL

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_KEY" \
  -H "Accept: application/json" \
  "$JIRA_ENDPOINT/rest/api/3/search?jql=project%3DSYM%20AND%20status%3D%27To%20Do%27&fields=summary,status,assignee"
```

Common JQL patterns:

| Goal                        | JQL snippet                                  |
|-----------------------------|----------------------------------------------|
| Open issues in project      | `project=SYM AND status="To Do"`            |
| Assigned to current user    | `project=SYM AND assignee=currentUser()`    |
| Recently updated            | `project=SYM AND updated >= -7d`            |
| Issues in a sprint          | `project=SYM AND sprint in openSprints()`   |

The `fields` query param limits the response to specific fields — always
include it to avoid large payloads.

## Naming conventions

### Branch names

Derive the branch name from the issue key and summary:

```
sym-1-short-summary-slug
```

Rules:
- Lowercase the issue key: `SYM-1` → `sym-1`
- Append a slug of the summary (lowercase, words joined with `-`, ≤5 words)
- Example: `SYM-42 Fix login timeout` → `sym-42-fix-login-timeout`

### Commit references

Prefix every commit that relates to a Jira issue with the issue key:

```
SYM-1: brief description of the change
```

Example:

```
SYM-42: fix token expiry check in auth middleware
```

## Usage rules

- Always fetch available transitions before posting one — never hardcode
  transition IDs, they vary per project and instance.
- Keep `fields` parameter in search requests to limit response size.
- Use `$JIRA_ENDPOINT` without a trailing slash.
- The Jira Cloud REST API version used here is `v3` (`/rest/api/3/`).
- For pagination, pass `startAt` and `maxResults` query params to `/search`.
- A successful comment POST returns HTTP 201; a successful transition POST
  returns HTTP 204 (no body).
