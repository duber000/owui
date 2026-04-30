# TODO

## Resource and Prompt Bridge

The bridge currently surfaces only **tools** from connected MCP servers. Servers
can also expose **resources** (documents, configs, entity data) and **prompts**
(reusable instruction templates) that owui ignores entirely.

### What to add

**`bridge.kuki`**

- Extend `BridgeServer` with `Resources list of mcp.ClientResource` and
  `Prompts list of mcp.ClientPrompt`.
- In `connectBridges`, after `mcp.ListTools`, also call `mcp.ListResources` and
  `mcp.ListPrompts` (both are allowed to fail silently — not all servers expose
  them).
- Add `callBridgeResource(ctx, b, uri) (string, error)` using `mcp.ReadResource`
  — mirrors `callBridgeTool` but dispatches by URI to the server that owns it.

**`agent.kuki`**

- Build a resource index string from discovered resources and inject it into the
  system prompt so the LLM knows what it can read passively.
- Register a synthetic `read_resource` tool (schema: `{uri: string}`) that calls
  `callBridgeResource` — this lets the model fetch resource content mid-turn
  without needing a special code path in `runAgent`.

**`main.kuki`** (optional)

- Add a `resources` subcommand that lists discovered resources across all
  connected servers, similar to the existing `tools` subcommand.
- Add a `prompts` subcommand for browsing available prompt templates.

### Relevant stdlib functions

```kukicha
# Discovery (call at connect time, inside connectBridges)
resources := mcp.ListResources(ctx, session) onerr continue
prompts   := mcp.ListPrompts(ctx, session)   onerr continue

# Reading (call at dispatch time, inside callBridgeResource)
result := mcp.ReadResource(ctx, session, uri) onerr return "", error "{error}"
text   := result.Text
```

### Notes

- `mcp.ClientResource` has fields `URI`, `Name`, `Description`, `MIMEType`.
- `mcp.ClientPrompt` has fields `Name`, `Description`, and `Arguments`.
- `mcp.ReadResource` returns a `*mcp.ReadResourceResult` with a `Text` field
  (same shape as `CallTool` result).
- URI-to-server routing follows the same prefix/exact-match pattern as the
  tool `ToolMap` — build a `ResourceMap map of string to string` keyed by URI,
  value = server name.
