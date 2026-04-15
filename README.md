# owui — CLI agent: Open WebUI + Open Terminal via MCP

A terminal-native agent that gets its brain from [Open WebUI](https://github.com/open-webui/open-webui) (LLM) and its hands from [Open Terminal](https://github.com/open-webui/open-terminal) (sandboxed shell), connected via the [Model Context Protocol](https://modelcontextprotocol.io).

```
┌─────────┐     tools (from MCP)       ┌──────────────┐
│         │ ──── chat/completions ────→ │  Open WebUI   │
│  owui   │ ←─── stream + tool_calls ── │  (LLM)        │
│  (CLI)  │                             └───────────────┘
│         │     MCP (streamable-http)   ┌───────────────┐
│         │ ──── CallTool ────────────→ │ Open Terminal  │
│         │ ←─── results ────────────── │ (MCP server)   │
└─────────┘                             └───────────────┘
          └── built-in sandboxed tools ─────────────────┘
               read_file / write_file / list_dir
               search_files / grep_files / run_command
```

**Tools are discovered dynamically.** At startup, owui connects to each configured MCP server and calls `ListTools` — whatever endpoints your instance exposes become available to the model automatically. No hardcoded tool definitions, no version drift. Tool names are prefixed with the server name (e.g. `terminal_execute_command`) so there are no collisions across servers.

**Built-in tools run without any MCP server.** Even with no MCP configured, owui exposes a sandboxed set of file and shell tools using kernel-level path confinement (`os.Root`) and an explicit command allowlist.

Built with [Kukicha](https://kukicha.org) and its stdlib (`stdlib/llm`, `stdlib/mcp`, `stdlib/sandbox`, `stdlib/netguard`, `stdlib/shell`).

## Install

```bash
git clone https://github.com/you/owui.git && cd owui
kukicha build owui/
# binary at ./owui (or ./bin/owui depending on your build output)
```

## Configure

```bash
# Environment variables
export OWUI_WEBUI_URL="http://localhost:3000"
export OWUI_WEBUI_API_KEY="sk-..."
export OWUI_MODEL="llama3.1"
export OWUI_TERMINAL_MCP_URL="http://127.0.0.1:9000/mcp"
export OWUI_TERMINAL_MCP_API_KEY="..."   # optional, for authenticated servers
export OWUI_SANDBOX_DIR="/path/to/workdir"  # default: cwd

# Or interactive wizard (saves to ~/.config/owui/config.json)
owui configure

# Verify
owui health
owui tools     # see all tools from MCP servers + built-ins
owui models    # see what LLMs are available
```

Config is loaded with priority: **env vars > `~/.config/owui/config.json` > defaults**.

## Usage

### Agent mode (LLM + tools)

```bash
# One-shot
owui "set up a python project with fastapi and write a hello world"

# Pipe context
cat error.log | owui "diagnose and fix this"

# Raw output for piping
owui "list installed python packages" --raw | grep torch

# Interactive chat
owui -c

# Seed the system prompt
owui -c -S "you are a senior Go developer. be terse."

# Pipe context then chat
cat main.go | owui -c "review this code"
```

If an `AGENTS.md` file exists in the current directory, owui loads it automatically and appends it to the system prompt as project context.

Tool calls are shown on stderr:
```
tools: 18 available | sandbox: /home/user/project
-> terminal_execute_command {"command":"ls -la /workspace"}
<- terminal_execute_command total 24 drwxr-xr-x 3 user user 4096...
-> write_file {"path":"main.py","content":"from fa...
<- write_file wrote 342 bytes to main.py
The FastAPI project is set up...
(3 tool rounds)
```

### Inspect

```bash
owui tools     # list all tools (built-ins + MCP-discovered, prefixed by server)
owui models    # list available LLMs from Open WebUI
owui health    # check connectivity to Open WebUI and each MCP server
```

## Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--chat` | `-c` | Interactive chat mode |
| `--model` | `-m` | Override model for this run |
| `--system` | `-S` | Override system prompt |
| `--raw` | | Raw output, no ANSI formatting |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OWUI_WEBUI_URL` | `http://localhost:3000` | Open WebUI base URL |
| `OWUI_WEBUI_API_KEY` | *(required)* | Open WebUI API key |
| `OWUI_MODEL` | `llama3.1` | Default model |
| `OWUI_TERMINAL_MCP_URL` | `http://127.0.0.1:9000/mcp` | Open Terminal MCP endpoint |
| `OWUI_TERMINAL_MCP_API_KEY` | | API key for authenticated MCP servers |
| `OWUI_SANDBOX_DIR` | cwd | Root directory for built-in file/shell tools |

## Architecture

```
main.kuki          CLI entrypoint — flag parsing, subcommand dispatch,
                   chat loop, one-shot agent runner
agent.kuki         Agent loop: LLM → tool calls → bridge dispatch → repeat
                   (streaming and tool calls work in the same round)
bridge.kuki        Multi-server MCP client — discovers tools at connect time,
                   converts MCP schemas to stdlib/llm tool format,
                   dispatches CallTool; prefixes tool names with server name
config.kuki        Config loading (env > ~/.config/owui/config.json > defaults)
                   Supports multiple named MCP servers, IP allow/block lists,
                   command allowlist, and sandbox root
local_tools.kuki   Built-in sandboxed tools — no MCP server required
                   File ops via stdlib/sandbox (os.Root path confinement)
                   Shell via stdlib/shell with an explicit command allowlist
                   Network filtering via stdlib/netguard (SSRF protection)
```

### Built-in tools

| Tool | Description |
|------|-------------|
| `read_file` | Read a file within the sandbox |
| `write_file` | Write or overwrite a file within the sandbox |
| `list_dir` | List directory contents within the sandbox |
| `search_files` | Glob-search for files by name pattern |
| `grep_files` | Search file contents by regex or literal text |
| `run_command` | Run an allowlisted command in the sandbox directory |

Default command allowlist: `cargo cat cp diff echo env find git go grep head ls make mkdir mv node npm pip3 pwd python3 rm sort tail touch uniq wc which`. Override with `cmd_allow` in the config file.

### Security

- **Path confinement** — `stdlib/sandbox` uses `os.Root` (kernel-level) so file tools cannot escape the sandbox root, even with symlinks or `..` traversal.
- **Command allowlist** — `run_command` rejects any binary not in the configured allowlist.
- **Network guard** — set `ip_allow` or `ip_block` in the config file to restrict outbound HTTP from built-in tools via `stdlib/netguard` (includes DNS rebinding protection).

### Multi-server MCP

Additional MCP servers can be added to `~/.config/owui/config.json`:

```json
{
  "mcp_servers": {
    "terminal": { "url": "http://127.0.0.1:9000/mcp" },
    "browser":  { "url": "http://127.0.0.1:9001/mcp", "api_key": "sk-..." }
  }
}
```

Tools from each server are prefixed with the server name (`terminal_execute_command`, `browser_navigate`, etc.) and are available to the LLM automatically.

## Prerequisites

- Open WebUI running (provides the LLM via `/api/chat/completions`)
- *(optional)* Open Terminal running with MCP enabled:
  ```bash
  pip install open-terminal[mcp]
  open-terminal mcp --transport streamable-http
  ```
  Without Open Terminal, the built-in sandboxed tools are still available.

## License

MIT
