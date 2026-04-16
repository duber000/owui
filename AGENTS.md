<!-- kukicha:start -->
## Writing Kukicha

Kukicha is a strict superset of Go — all valid Go compiles as-is. **Always
write Kukicha syntax** (`and`/`or`/`not`, `list of T`, `onerr`, pipes, enums)
and use Kukicha's stdlib (`stdlib/*`) over raw Go packages. Fall back to Go
only when Kukicha has no equivalent.

When `kukicha init` is run, this file is created and the stdlib is extracted
into `.kukicha/stdlib/`. Browse the source files there for full API details
beyond what this reference covers.

### Getting Started

```kukicha
# hello.kuki — minimal program
import "stdlib/string"

func main()
    name := "world"
    print("Hello {string.ToUpper(name)}!")
```

Run: `kukicha run hello.kuki` · Build: `kukicha build hello.kuki`

**Multi-file packages:** `kukicha build myapp/` merges all `.kuki` files. One file defines `func main()`, others use `func init()`. All files need the same `petiole` declaration (Go's `package`).

### Syntax Reference

| Kukicha (preferred) | Go equivalent |
|---------------------|---------------|
| `and`, `or`, `not` | `&&`, `\|\|`, `!` |
| `equals`, `isnt` | `==`, `!=` |
| `empty` | `nil` |
| `list of string` | `[]string` |
| `map of string to int` | `map[string]int` |
| `reference User` / `reference of x` | `*User` / `&x` |
| `dereference ptr` | `*ptr` |
| `func Method on t T` | `func (t T) Method()` |
| `many args` | `args...` |
| `make channel of T` | `make(chan T)` |
| `send val to ch` / `receive from ch` | `ch <- val` / `<-ch` |
| `when` / `otherwise` | `case` / `default` |
| `for item in items` | `for _, item := range items` |
| `for i from 0 to 10` | `for i := 0; i < 10; i++` |
| `for i from 0 through 10` | `for i := 0; i <= 10; i++` |
| 4-space indentation | `{ }` braces |

`func`/`var`/`const` have aliases `function`/`variable`/`constant` — use the short forms in production code; reserve the long forms for beginner tutorials only.

### Variables and Functions

```kukicha
count := 42           # inferred type
count = 100           # reassignment

func Add(a int, b int) int
    return a + b

func Divide(a int, b int) int, error
    if b equals 0
        return 0, error "division by zero"
    return a / b, empty

# Default parameter + named argument at call site
func Greet(name string, greeting string = "Hello") string
    return "{greeting}, {name}!"

result := Greet("Alice", greeting: "Hi")
files.Copy(from: src, to: dst)
```

### Strings and Interpolation

```kukicha
greeting := "Hello {name}!"          # {expr} is interpolated — replaces fmt.Sprintf
json := "key: \{value\}"             # \{ \} for literal braces
path := "{dir}\sep{file}"            # \sep → OS path separator at runtime

# Raw strings (backticks) — no escapes, no interpolation
prompt := `Reply JSON: {severity:1-5, kind, summary}`

# Escape sequences: \n \t \r \\ \" \' \xHH \0-\377
# Number literals: 42, 0xFF, 0o755, 0b1010, 3.14
```

### Types

```kukicha
type Repo
    name  string as "name"            # JSON field alias
    stars int    as "stargazers_count"
    tags  list of string

# Function type alias
type Handler func(context.Context, string) (string, error)

# Transparent type alias (type X = Y — identical types, cross-package assertions work)
type TextContent = mcp.TextContent
```

### Enums

```kukicha
enum Status
    OK = 200
    NotFound = 404
    Error = 500

status := Status.OK    # dot access → transpiles to StatusOK

# Exhaustiveness-checked switch
switch status
    when Status.OK
        print("ok")
    when Status.NotFound, Status.Error
        print("problem")
```

- Underlying type (int or string) inferred from values — all must match
- Compiler warns on missing cases unless `otherwise` present
- Integer enums warn if no case has value 0
- Auto-generated `String()` method

### Variant Enums (Tagged Unions)

```kukicha
enum Shape
    Circle
        radius float64
    Rectangle
        width  float64
        height float64
    Point

# Pattern matching
func area(s Shape) float64
    switch s as v
        when Circle
            return 3.14159 * v.radius * v.radius
        when Rectangle
            return v.width * v.height
        when Point
            return 0.0

# Single-case check with binding
if s is Circle as c
    return 3.14159 * c.radius * c.radius
```

- Cannot mix value cases (`= literal`) and variant cases in the same enum
- `is` for bool checks; `is CaseName as v` binds in `if` blocks (top-level condition only)

### Methods

```kukicha
func Display on todo Todo string
    return "{todo.id}: {todo.title}"

func SetDone on todo reference Todo       # pointer receiver
    todo.done = true
```

### Error Handling (`onerr`)

The caught error is always `{error}` — **never** `{err}`. Using `{err}` is a compile error. Use `onerr as e` to rename.

```kukicha
data := fetch.Get(url) onerr panic "failed: {error}"        # stop with message
data := fetch.Get(url) onerr return                         # propagate (raw error, zero values)
data := fetch.Get(url) onerr return empty, error "{error}"  # propagate (wrap)
data := fetch.Get(url) onerr return {}, error "{error}"     # propagate with untyped zero struct
port := getPort()      onerr 8080                           # default value
_    := riskyOp()      onerr discard                        # ignore
v    := parse(item)    onerr continue                       # skip in loop
v    := parse(item)    onerr break                          # exit loop
data := fetch.Get(url) onerr explain "context hint"         # wrap and propagate

# Block form
users := parse() onerr
    print("failed: {error}")
    return

# Block form with named alias
users := parse() onerr as e
    print("failed: {e}")    # {e} and {error} both work
    return
```

### Pipes

```kukicha
result := data |> parse() |> transform()

# _ placeholder for non-first argument
todo |> json.MarshalWrite(w, _)   # → json.MarshalWrite(w, todo)

# Bare identifier as target
data |> print                     # → fmt.Println(data)

# Pipeline-level onerr — catches errors from any step
items := fetch.Get(url)
    |> fetch.CheckStatus()
    |> fetch.Json(list of Repo)
    onerr panic "{error}"

# Piped switch
user.Role |> switch
    when "admin"
        grantAccess()
    otherwise
        checkPermissions()

# Shorthand .Field / .Method() — pipe context only
name := user |> .Name
```

### Control Flow

```kukicha
if count equals 0
    return "empty"
else if count < 10
    return "small"

for item in items
    process(item)

for i from 0 to 10        # 0..9 (exclusive)
for i from 0 through 10   # 0..10 (inclusive)
for i from 10 through 0   # descending

for                        # infinite loop (use break to exit)
    msg := receive from ch
    if msg equals "quit"
        break

# If-expression (ternary)
result := if condition then "yes" else "no"

# If with init statement
if val, ok := cache[key]; ok
    return val

switch command
    when "fetch", "pull"
        fetchRepos()
    otherwise
        print("Unknown: {command}")

# Bare switch (condition-based)
switch
    when stars >= 1000
        print("popular")
    otherwise
        print("new")

# Type switch
switch event as e
    when string
        print(e)
    when reference TaskEvent
        print(e.Status)
```

### Lambdas

Parameter types are inferred from context — explicit annotations are optional.

```kukicha
repos   |> slice.Filter(r => r.stars > 100)     # inferred type
entries |> sort.ByKey(e => e.name)
repos   |> sort.By((a, b) => a.stars < b.stars)  # two params

# Block lambda (multi-statement)
repos |> slice.Filter(r =>
    name := r.name |> strpkg.ToLower()
    return name |> strpkg.Contains("go")
)
```

### Collections and Literals

```kukicha
items  := list of string{"a", "b", "c"}
config := map of string to int{"port": 8080}
last   := items[-1]    # negative indexing

# Untyped literals — type inferred from context
func makeConfig() Config
    return {host: "localhost", port: 8080}    # inferred from return type

applyConfig({host: "prod", port: 443})        # inferred from parameter
```

Inference works in return statements, `onerr return`, function arguments, assignments, and typed list elements.

### Variadic Arguments (`many`)

```kukicha
func Sum(many numbers int) int
    total := 0
    for n in numbers
        total = total + n
    return total

nums := list of int{1, 2, 3}
result := Sum(many nums)    # spread a slice
```

### Type Casts and Assertions

```kukicha
n := x as int                         # type conversion
result, ok := value.(string)          # safe type assertion
s := value.(string)                   # panics if wrong type
```

### Concurrency

```kukicha
ch := make channel of string
send "message" to ch
msg := receive from ch
go doWork()

# Multi-statement goroutine
go
    defer wg.Done()
    doWork()

# Select
select
    when receive from done
        return
    when msg := receive from ch
        print(msg)
    when send "ping" to out
        print("sent")
    otherwise
        print("nothing ready")
```

### Defer

```kukicha
defer resource.Close()

# Block form (emits defer func() { ... }())
defer
    if r := recover(); r != empty
        tx.Rollback()
        panic(r)
```

### Imports and Aliases

```kukicha
import "stdlib/slice"
import "stdlib/ctx"       as ctxpkg     # clashes with local 'ctx'
import "stdlib/db"        as dbpkg      # clashes with local 'db'
import "stdlib/errors"    as errs       # clashes with 'errors'
import "stdlib/json"      as jsonpkg    # clashes with 'encoding/json'
import "stdlib/string"    as strpkg     # clashes with 'string' type
import "stdlib/container" as docker     # clashes with 'container' vars
import "stdlib/http"      as httphelper # clashes with 'net/http'
import "stdlib/net"       as netutil    # clashes with 'net' package

import "github.com/jackc/pgx/v5" as pgx  # external package
```

Always use these aliases when the package name clashes — collisions cause compile errors.

### Commands

```bash
kukicha init [module]          # init project (go mod init + extract stdlib)
kukicha check file.kuki        # validate syntax
kukicha check --json file.kuki # JSON diagnostics
kukicha run file.kuki          # transpile + compile + run
kukicha build file.kuki        # compile to binary
kukicha build myapp/           # build directory
kukicha build --wasm file.kuki # WebAssembly output
kukicha fmt -w file.kuki       # format in place
kukicha brew file.kuki         # convert .kuki to standalone Go
kukicha pack skill.kuki        # package skill with SKILL.md + binary
kukicha audit                  # vulnerability check
```

---

### Stdlib Packages

Browse `.kukicha/stdlib/` for full API details. Key functions listed below.

#### Collections & Strings

**slice** — `Filter`, `Map`, `GroupBy`, `Sort`, `SortBy`, `First`, `Last`, `Contains`, `Unique`, `Chunk`, `Find`, `FindOr`, `Get`, `GetOr`, `FirstOr`, `LastOr`, `Pop`, `Shift`, `Reverse`, `Concat`, `IndexOf`, `IsEmpty`

```kukicha
active := slice.Filter(items, x => x.active)
names  := slice.Map(items, x => x.name)
first  := slice.FirstOr(items, defaultVal)
```

**maps** — `Keys`, `Values`, `Contains`, `Has`, `Merge`, `Filter`, `MapValues`, `Pick`, `Omit`, `SortedKeys`

**set** — `From`, `Add`, `AddIn`, `Remove`, `Contains`, `Union`, `Intersect`, `Difference`, `IsSubset`, `Equal`, `ToSlice`

**sort** — `Strings`, `Ints`, `Float64s`, `By`, `ByKey`, `Reverse`

```kukicha
sorted := repos |> sort.ByKey(r => r.name)
```

**string** (as `strpkg`) — `Split`, `Join`, `ToUpper`, `ToLower`, `Contains`, `HasPrefix`, `HasSuffix`, `Replace`, `ReplaceAll`, `Trim`, `TrimSpace`, `Fields`, `Lines`, `PadRight`, `PadLeft`, `IsEmpty`, `IsBlank`

**regex** — `Match`, `Find`, `FindAll`, `FindGroups`, `Replace`, `Split`, `MustCompile` + compiled variants

**iterator** — Lazy iteration (Go 1.23 iter.Seq): `Values`, `Filter`, `Map`, `FlatMap`, `Take`, `Skip`, `Enumerate`, `Chunk`, `Zip`, `Reduce`, `Collect`, `Any`, `All`, `Find`

```kukicha
names := repos
    |> iterator.Values()
    |> iterator.Filter((r Repo) => r.Stars > 100)
    |> iterator.Map((r Repo) => r.Name)
    |> iterator.Take(5)
    |> iterator.Collect()
```

**cast** — `SmartInt`, `SmartFloat64`, `SmartBool`, `SmartString`

#### Data & Encoding

**json** (as `jsonpkg`) — `Marshal`, `MarshalPretty`, `Unmarshal`, `MarshalWrite`, `UnmarshalRead`

**parse** — `Json`, `JsonLines`, `Csv`, `CsvWithHeader`, `Yaml`, `YamlPretty`

**encoding** — `Base64Encode`, `Base64Decode`, `HexEncode`, `HexDecode`

**template** — `RenderSimple` (text), `HTMLRenderSimple` (auto-escaped HTML)

#### I/O & Files

**files** — `Read`, `ReadString`, `Write`, `Append`, `Exists`, `IsDir`, `Copy`, `Move`, `Delete`, `List`, `ListRecursive`, `MkDirAll`, `TempFile`, `TempDir`, `Join`, `Watch`

```kukicha
data := files.Read("config.json") onerr panic "{error}"
files.Copy(from: src, to: dst) onerr panic "{error}"
```

**sandbox** — Filesystem sandboxing (use in HTTP handlers): `New`, `Read`, `Write`, `List`, `Exists`

```kukicha
box := sandbox.New("/var/data") onerr return
content := sandbox.Read(box, userPath) onerr return   # can't escape root
```

**shell** — `Run` (fixed literals only), `Output` (variable args), `New`/`Dir`/`Env`/`Execute` (builder)

```kukicha
diff := shell.Run("git diff --staged") onerr panic "{error}"
out  := shell.Output("git", "log", "--oneline", branch) onerr panic "{error}"
```

#### HTTP & Networking

**fetch** — HTTP client with builder, auth, retry, SSRF protection

```kukicha
# Typed JSON decode
repos := fetch.Get(url)
    |> fetch.CheckStatus()
    |> fetch.Json(list of Repo) onerr panic "{error}"

# fetch.Json type hint: list of T → array, empty T → object, map of K to V → map

# Builder: auth, timeout, retry
resp := fetch.New(url)
    |> fetch.BearerAuth(token)
    |> fetch.Retry(3, 500)
    |> fetch.Do() onerr panic "{error}"
```

Key: `Get`, `SafeGet` (SSRF-safe), `Post`, `Json`, `Text`, `Bytes`, `CheckStatus`, `URLTemplate`, `URLWithQuery`, `New`/`BearerAuth`/`Timeout`/`Retry`/`MaxBodySize`/`Do`, `DownloadTo`

**http** (as `httphelper`) — Response helpers + security

```kukicha
httphelper.JSON(w, data)                                       # 200 OK
httphelper.JSONCreated(w, data)                                 # 201
httphelper.JSONNotFound(w, "not found")                         # 404
httphelper.JSONBadRequest(w, "bad input")                       # 400
httphelper.ReadJSONLimit(r, 1<<20, reference of input) onerr return
httphelper.SafeRedirect(w, r, url, "myapp.com") onerr return
httphelper.SetSecureHeaders(w)
```

**html** — Component-style rendering with auto-escaping: `Render`, `Escape`, `Attr`, `Embed`, `WriteTo`, `Join`, `Map`, `When`, `WhenElse`

```kukicha
page := html.Render("<h1>{html.Escape(title)}</h1>")
html.WriteTo(w, page) onerr discard
```

**net** (as `netutil`) — `ParseIP`, `ParseCIDR`, `Contains`, `IsPrivate`, `IsLoopback`

**netguard** — SSRF protection: `NewSSRFGuard`, `NewAllow`, `NewBlock`, `Check`, `HTTPClient`, `HTTPTransport`

#### CLI & System

**cli** — Argument parsing: `New`, `AddFlag`, `Action`, `RunApp`, `Command`, `GetString`, `GetInt`, `Fatal`, `Error`, `Warn`

```kukicha
app := cli.New("myapp") |> cli.AddFlag("port", "Port", "8080") |> cli.Action(run)
cli.RunApp(app) onerr panic "{error}"
data := loadConfig() onerr cli.Fatal("config error: {error}")
```

**input** — `ReadLine`, `Prompt`, `Confirm`, `Choose`

**table** — Terminal tables: `New`, `AddRow`, `Print`, `PrintWithStyle` (`"plain"`, `"box"`, `"markdown"`)

**color** — ANSI terminal colors: `Bold`, `Dim`, `Red`, `Green`, `Yellow`, `Blue`, `Cyan`, `Gray`, `BrightRed`, `Error`, `Warn`, `Success`, `Info`, `Muted`, `Enabled`, `SetEnabled`

```kukicha
print(color.Bold("Title"))
print(color.Red("error: something went wrong"))
print(color.Success("All tests passed"))
color.SetEnabled(false)  # disable in tests
```

**env** — Typed env vars with onerr: `Get`, `GetOr`, `GetInt`, `GetBool`, `Set`, `All`

**must** — Panic-on-error startup: `Env`, `EnvOr`, `EnvInt`, `EnvIntOr`, `True`, `NotEmpty`

```kukicha
apiKey := must.Env("API_KEY")
port   := must.EnvIntOr("PORT", 8080)
debug  := env.GetBool("DEBUG") onerr false
```

#### Concurrency & Resilience

**concurrent** — `Parallel`, `ParallelWithLimit`, `Map`, `MapWithLimit`, `Go`

```kukicha
results := concurrent.Map(urls, url => check(url))
results := concurrent.MapWithLimit(repos, 4, r => fetchDetails(r))
```

**ctx** (as `ctxpkg`) — `Background`, `WithTimeout`, `Cancel`, `Done`, `Value`

**retry** — `New`, `Attempts`, `Delay`, `Linear`, `Sleep`

**datetime** — `Format`, `Parse`, `Now`, `AddDays`, `Seconds`, `Sleep`; Constants: `ISO8601`, `RFC3339`, `Date`, `Time`

#### Data & Storage

**db** (alias `dbpkg` when local `db` variable exists) — SQL with struct scanning: `Open`, `Close`, `Query`, `QueryRow`, `Exec`, `ScanAll`, `ScanOne`, `ScanRow`, `Transaction`, `Count`, `Exists`

```kukicha
pool := db.Open("postgres", connStr) onerr panic "{error}"
defer db.Close(pool)
users := db.Query(pool, "SELECT id, name FROM users WHERE active = $1", true)
    |> db.ScanAll(list of User{}) onerr panic "{error}"
```

**sqlite** — SQLite convenience (WAL, foreign keys, busy timeout by default): `Open`, `OpenMemory`, `OpenWith`, `Pragma`, `Tables`, `TableExists`, `BatchExec`, `Backup`, `Dump`, `CreateFunction`, `CreateFunctionFloat`, `CreateFunctionInt`, `CreateFunctionBool`, `CreateBlobFunction`, `CreateBlobFunctionFloat`

```kukicha
pool := sqlite.Open("/tmp/app.db") onerr panic "{error}"
defer db.Close(pool)
# All queries use stdlib/db — same Query/Exec/ScanAll API
```

#### Security & Crypto

**crypto** — `SHA256`, `HMAC`, `RandomToken`, `RandomBytes`, `Equal` (constant-time)

**validate** — `Email`, `URL`, `NotEmpty`, `MinLength`, `MaxLength`, `InRange`, `Matches`, `NoHTML`, `SafeFilename`

**random** — `String`, `Alphanumeric`, `Int`, `Float`

**errors** (as `errs`) — `Wrap`, `Opaque`, `Is`, `New`, `Join`, `NewPublic`, `Public`

#### DevOps & Infrastructure

**container** (as `docker`) — Docker/Podman: `Connect`, `ListContainers`, `ListImages`, `Pull`, `Run`, `Stop`, `Remove`, `Build`, `Logs`, `Wait`, `Exec`

**git** — Git/GitHub via `gh`: `ListTags`, `TagExists`, `DefaultBranch`, `CreateRelease`, `PreviewRelease`

**semver** — `Parse`, `Bump`, `Format`, `Valid`, `Compare`, `Highest`

**obs** — Structured logging: `New`, `Component`, `Info`, `Warn`, `Error`, `Start`, `Stop`

#### AI & Agents

**llm** — LLM calls: `New`/`Ask`/`Send` (OpenAI), `NewResponse`/`RAsk` (OpenResponses), `NewMessages`/`MAsk` (Anthropic); all support `Retry` and `Stream` variants

```kukicha
reply := llm.New("openai:gpt-4o-mini") |> llm.Retry(3, 2000) |> llm.Ask("Hello!") onerr panic "{error}"
```

**mcp** — MCP server + client: `New`, `Tool`, `Serve`, `Connect`, `BearerConnect`, `ListTools`, `CallTool`

```kukicha
# Server
server := mcp.New("stock-tool", "1.0.0")
schema := mcp.Schema(list of mcp.SchemaProperty{
    mcp.Prop("symbol", "string", "Ticker symbol"),
}) |> mcp.Required(list of string{"symbol"})
mcp.Tool(server, "get_price", "Get stock price", schema, handler)
mcp.Serve(server) onerr panic "{error}"

# Client
session := mcp.Connect(ctx, url) onerr panic "{error}"
defer mcp.Close(session)
result := mcp.CallTool(ctx, session, "get_price", args) onerr panic "{error}"
```

**skills** — Agent SKILL.md discovery: `Discover`, `AgentSkills`, `ClaudeSkills`

#### External Packages (separate modules)

**game** (WASM-only) — 2D game lib: `Window`, `Run`, `DrawRect`, `DrawCircle`, `DrawText`, `IsKeyDown`, `MousePosition`

**infer** / **ort** / **webinfer** — ML inference (`github.com/kukichalang/infer`)

---

**All packages:** `cast`, `cli`, `concurrent`, `container`, `crypto`, `ctx`, `datetime`, `db`, `encoding`, `env`, `errors`, `fetch`, `files`, `game`, `git`, `html`, `http`, `infer`, `input`, `iterator`, `json`, `llm`, `maps`, `mcp`, `must`, `net`, `netguard`, `obs`, `ort`, `parse`, `random`, `regex`, `retry`, `sandbox`, `semver`, `set`, `shell`, `skills`, `slice`, `sort`, `sqlite`, `string`, `table`, `template`, `test`, `validate`, `webinfer`

---

### Security — Compiler-Enforced Checks

The compiler **rejects** these patterns in HTTP handlers (functions with `http.ResponseWriter`):

| Pattern | Fix |
|---------|-----|
| `httphelper.HTML(w, nonLiteral)` | `httphelper.SafeHTML(w, content)` |
| `fetch.Get(url)` in handler | `fetch.SafeGet(url)` |
| `files.Read(path)` in handler | `sandbox.New(root)` + `sandbox.Read(box, path)` |
| `shell.Run("cmd {var}")` | `shell.Output("cmd", arg)` |
| `httphelper.Redirect(w, r, nonLiteral)` | `httphelper.SafeRedirect(w, r, url, "host")` |
| `html.Render("<script>...")` | Static `.js` file with `<script src="...">` |

---

### Skills (Agent Tool Packaging)

```kukicha
# target: mcp
petiole weather

skill WeatherService
    description: "Provides weather forecasts."
    version: "1.0.0"

# ... MCP server implementation
```

`kukicha pack weather.kuki` produces a directory with `SKILL.md` manifest + compiled binary. Discover at runtime:

```kukicha
tools := skills.Discover("./tools") onerr panic "{error}"
```

---

### Testing

Test files use `*_test.kuki` with the table-driven pattern:

```kukicha
petiole slice_test

import "stdlib/slice"
import "stdlib/test"
import "testing"

type FirstCase
    name    string
    n       int
    wantLen int

func TestFirst(t reference testing.T)
    items := list of string{"a", "b", "c", "d", "e"}
    cases := list of FirstCase{
        FirstCase{name: "3 elements", n: 3, wantLen: 3},
        FirstCase{name: "n > length", n: 10, wantLen: 5},
    }
    for tc in cases
        t.Run(tc.name, (t reference testing.T) =>
            result := slice.First(items, tc.n)
            test.AssertEqual(t, len(result), tc.wantLen)
        )
```

Assertions: `AssertEqual`, `AssertNotEqual`, `AssertTrue`, `AssertFalse`, `AssertNoError`, `AssertError`, `AssertNotEmpty`, `AssertNil`, `AssertNotNil`.

---

### Pitfalls

**WaitGroups — always `defer wg.Done()` as first goroutine statement.** Explicit `wg.Done()` at the end is skipped if the task panics, hanging `wg.Wait()` forever.

**Context cancel — defer in the function that uses the resource, not the one that creates it:**

```kukicha
# WRONG — cancel fires when buildCmd returns, context is dead before use
func buildCmd() reference exec.Cmd
    h := ctxpkg.WithTimeout(ctxpkg.Background(), 30)
    defer ctxpkg.Cancel(h)
    return exec.CommandContext(ctxpkg.Value(h), name, many args)

# CORRECT — defer in Execute, which owns the resource's lifetime
func Execute() Result
    h := ctxpkg.WithTimeout(ctxpkg.Background(), 30)
    defer ctxpkg.Cancel(h)     # fires after Run()
    execCmd := exec.CommandContext(ctxpkg.Value(h), name, many args)
    ...
```

**Cleanup goroutines** — always provide a shutdown path (context or stop channel). Goroutines looping on a ticker leak if there's no stop signal.

**Never use `io.NopCloser` on a live response body** — it silences `Close()`, leaking TCP connections. Wrap with a type that delegates both `Read` and `Close`.

**Struct literals must be single-line** — multiline struct literals do not parse.

**`in` is not a membership operator** — use `slice.Contains(items, val)` or `set.Contains(s, val)`. `in` only works in `for` loops.

---

### Troubleshooting

| Error | Fix |
|-------|-----|
| `use {error} not {err} inside onerr` | Change `{err}` to `{error}`, or use `onerr as e` |
| `variable 'x' not used` | Use `_ := f()` to discard |
| `function must declare return type` | Add explicit return type: `func F() int` |
| `onerr return requires return type` | Use `onerr discard`, or add return type |
| `SSRF risk` / `path traversal` / `command injection` / `XSS risk` | See Security table above |
| `expected INDENT` | Check 4-space indentation (no tabs) |
| `expected 'when' or 'otherwise'` | Use `when`/`otherwise`, not `case`/`default` |

<!-- kukicha:end -->
