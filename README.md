# owui — CLI agent powered by any OpenAI-compatible LLM + MCP

A terminal-native agent that talks to any OpenAI-compatible LLM endpoint ([Open WebUI](https://github.com/open-webui/open-webui), [Hetzner Inference](https://docs.hetzner.com/general/company-and-policy/experiments/inference/), OpenAI, Ollama, …) and connects to any [MCP](https://modelcontextprotocol.io) servers for tools — [Open Terminal](https://github.com/open-webui/open-terminal), browser automation, custom services, whatever you wire up.

```
┌─────────┐     chat/completions        ┌────────────────┐
│         │ ────────────────────────→    │  LLM endpoint   │
│  owui   │ ←── stream + tool_calls ──  │  (Open WebUI /  │
│  (CLI)  │                             │   Hetzner /     │
│         │                             │   OpenAI / …)   │
│         │     MCP (streamable-http)   └────────────────┘
│         │ ──── CallTool ────────────→ ┌────────────────┐
│         │ ←─── results ────────────── │  MCP Server(s)  │
└─────────┘                             └────────────────┘
          └── built-in sandboxed tools ─────────────────┘
               read_file / write_file / list_dir
                search_files / grep_files / run_command
```

**Tools are discovered dynamically.** At startup, owui connects to each configured MCP server and calls `ListTools` — whatever endpoints your instance exposes become available to the model automatically. No hardcoded tool definitions, no version drift. Tool names are prefixed with the server name (e.g. `terminal_execute_command`) so there are no collisions across servers.

**Built-in tools run without any MCP server.** Even with no MCP configured, owui exposes a sandboxed set of file and shell tools using kernel-level path confinement (`os.Root`) and an explicit command allowlist.

Built with [Kukicha](https://kukicha.org) and its stdlib (`stdlib/llm/chat`, `stdlib/mcp`, `stdlib/sandbox`, `stdlib/netguard`, `stdlib/shell`).

## Install

```bash
git clone https://github.com/you/owui.git && cd owui
kukicha build .
# binary at ./owui
```

## Configure

owui targets any OpenAI-compatible endpoint via a **provider preset** that fills in the base URL, chat-completions path, models-list path, and the conventional API-key env var. Any of those can be overridden individually.

| Provider | Base URL | Chat path | Models path | API key env var |
|----------|----------|-----------|-------------|-----------------|
| `openwebui` *(default)* | `http://localhost:3000` | `/api/chat/completions` | `/api/models` | — |
| `hetzner` | `https://inference.hetzner.com/api/v1` | `/chat/completions` | `/models` | `HETZNER_VLLM_API_KEY` |
| `openai` | `https://api.openai.com/v1` | `/chat/completions` | `/models` | `OPENAI_API_KEY` |
| `ollama` | `http://localhost:11434/v1` | `/chat/completions` | `/models` | — |
| `custom` | *(you set it)* | *(you set it)* | *(you set it)* | — |

```bash
# Hetzner — provider preset handles everything, just set the key
export OWUI_PROVIDER=hetzner
export HETZNER_VLLM_API_KEY="..."   # picked up via the preset
export OWUI_MODEL="Qwen/Qwen3.6-35B-A3B-FP8"

# Open WebUI — legacy fields still work (provider defaults to openwebui)
export OWUI_WEBUI_URL="http://localhost:3000"
export OWUI_WEBUI_API_KEY="sk-..."
export OWUI_MODEL="llama3.1"

# Or interactive wizard (saves to ~/.config/owui/config.json)
owui configure

# Verify
owui health
owui tools     # see all tools from MCP servers + built-ins
owui models    # see what LLMs are available
```

Config is loaded with priority: **env vars > `~/.config/owui/config.json` > provider preset > defaults**.

### Config file options

`~/.config/owui/config.json` accepts the following options. Environment variables
override only the fields listed in the table above.

| Option | Default | Description |
|--------|---------|-------------|
| `provider` | `openwebui` | LLM backend preset. One of `openwebui`, `hetzner`, `openai`, `ollama`, `custom`. |
| `llm_base_url` | *(from preset)* | Override the LLM base URL. |
| `llm_api_key` | *(from preset/env)* | Override the LLM API key. |
| `chat_path` | *(from preset)* | Override the chat-completions path appended to `llm_base_url`. |
| `models_path` | *(from preset)* | Override the models-list path appended to `llm_base_url`. |
| `webui_url` | `http://localhost:3000` | *(legacy)* Open WebUI base URL. Only consulted when `provider` is `openwebui`. |
| `webui_api_key` | | *(legacy)* Open WebUI API key. Only consulted when `provider` is `openwebui`. |
| `model` | `llama3.1` | Model sent to the LLM endpoint. |
| `terminal_mcp_url` | `http://127.0.0.1:9000/mcp` | URL for the legacy `terminal` MCP server entry. |
| `terminal_mcp_api_key` | | API key for the legacy `terminal` MCP server entry. |
| `mcp_servers` | `{}` | Named MCP server configurations. Each server accepts `url`, optional `api_key`, and optional `disabled`. |
| `built_in_tools` | `true` | Enables the built-in sandboxed file and command tools. Set to `false` to expose MCP tools only. |
| `max_tool_rounds` | `15` | Maximum LLM tool-call rounds per request. |
| `sandbox_dir` | current working directory | Sandbox root for built-in file and command tools. |
| `cmd_allow` | built-in allowlist | Commands permitted through `run_command`. Replaces the default allowlist when non-empty. |
| `ip_allow` | `[]` | Allowed IP/CIDR ranges for the built-in tools' network guard. |
| `ip_block` | `[]` | Blocked IP/CIDR ranges for the built-in tools' network guard. Ignored when `ip_allow` is set. |

Example — Hetzner:

```json
{
  "provider": "hetzner",
  "model": "Qwen/Qwen3.6-35B-A3B-FP8",
  "built_in_tools": true,
  "max_tool_rounds": 15,
  "sandbox_dir": "/path/to/workdir"
}
```

Example — Open WebUI (legacy fields still work):

```json
{
  "webui_url": "http://localhost:3000",
  "webui_api_key": "sk-...",
  "model": "llama3.1",
  "built_in_tools": true,
  "max_tool_rounds": 15,
  "sandbox_dir": "/path/to/workdir",
  "cmd_allow": ["git", "grep", "ls", "mkdir", "pwd"],
  "ip_allow": ["10.0.0.0/8"],
  "mcp_servers": {
    "terminal": { "url": "http://127.0.0.1:9000/mcp" },
    "browser":  { "url": "http://127.0.0.1:9001/mcp", "api_key": "sk-..." },
    "staging":  { "url": "http://127.0.0.1:9002/mcp", "disabled": true }
  }
}
```

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
| `OWUI_PROVIDER` | `openwebui` | LLM backend preset (`openwebui`/`hetzner`/`openai`/`ollama`/`custom`) |
| `OWUI_LLM_BASE_URL` | *(from preset)* | Override the LLM base URL |
| `OWUI_LLM_API_KEY` | *(from preset/env)* | Override the LLM API key |
| `OWUI_CHAT_PATH` | *(from preset)* | Override the chat-completions path |
| `OWUI_MODELS_PATH` | *(from preset)* | Override the models-list path |
| `OWUI_MODEL` | `llama3.1` | Default model |
| `OWUI_WEBUI_URL` | `http://localhost:3000` | *(legacy)* Open WebUI base URL (openwebui provider only) |
| `OWUI_WEBUI_API_KEY` | | *(legacy)* Open WebUI API key (openwebui provider only) |
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
                   converts MCP schemas to stdlib/llm/chat tool format,
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

Default command allowlist: `bd cat cp date diff echo find git grep head ls mkdir mv pwd rm sort tail touch uniq wc which`. Override with `cmd_allow` in the config file.

Set `"built_in_tools": false` in `~/.config/owui/config.json` to disable all built-in tools. MCP-provided tools remain available:

```json
{
  "built_in_tools": false
}
```

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
    "browser":  { "url": "http://127.0.0.1:9001/mcp", "api_key": "sk-..." },
    "staging":  { "url": "http://127.0.0.1:9002/mcp", "disabled": true }
  }
}
```

Tools from each server are prefixed with the server name (`terminal_execute_command`, `browser_navigate`, etc.) and are available to the LLM automatically.
Set `"disabled": true` on an MCP server to keep its configuration while preventing owui from connecting to it. `owui health` lists disabled servers without probing them.

## Prerequisites

- An OpenAI-compatible LLM endpoint. Any of:
  - [Open WebUI](https://github.com/open-webui/open-webui) running (provides the LLM via `/api/chat/completions`) — `provider: openwebui`
  - [Hetzner Inference API](https://docs.hetzner.com/general/company-and-policy/experiments/inference/) — `provider: hetzner`, key in `HETZNER_VLLM_API_KEY`
  - OpenAI API — `provider: openai`, key in `OPENAI_API_KEY`
  - [Ollama](https://ollama.com) running locally — `provider: ollama`
  - Any other OpenAI-compatible endpoint — `provider: custom` + `llm_base_url`/`chat_path`/`models_path`
- *(optional)* One or more MCP servers. For example, [Open Terminal](https://github.com/open-webui/open-terminal):
  ```bash
  pip install open-terminal[mcp]
  open-terminal mcp --transport streamable-http
  ```
  Without any MCP servers, the built-in sandboxed tools are still available.

## License

MIT
