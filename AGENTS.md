<!-- kukicha:start -->
## Writing Kukicha

Kukicha is a near-superset of Go: most Go compiles as-is, with a few exceptions (`range`, `case`/`default`, `struct {}`, `chan T`, `goto`, parenthesized `const ( ... )`) that have Kukicha replacements. **Always
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

| Kukicha (write this) | Go equivalent (avoid in `.kuki` files) |
|----------------------|----------------------------------------|
| `and`, `or`, `not` | `&&`, `\|\|`, `!` |
| `equals`, `isnt` | `==`, `!=` |
| `empty` | `nil` |
| `list of string` | `[]string` |
| `map of string to int` | `map[string]int` |
| `reference User` / `reference of x` | `*User` / `&x` |
| `dereference ptr` | `*ptr` |
| `name: Type` (params, receivers, lambdas) | `name Type` (bare; Go-compat input, not idiomatic) |
| `func Method on t: T` | `func (t T) Method()` (accepted as Go-compat input but not idiomatic) |
| `many args: T` | `args ...T` |
| `make channel of T` | `make(chan T)` |
| `send val to ch` / `receive from ch` | `ch <- val` / `<-ch` |
| `when` / `default` | `case` / `default` |
| `for item in items` | `for _, item := range items` |
| `for i from 0 to 10` | `for i := 0; i < 10; i++` |
| `for i from 0 through 10` | `for i := 0; i <= 10; i++` |
| 4-space indentation | `{ }` braces |

`func`/`var`/`const` have aliases `function`/`variable`/`constant`: use the short forms in production code; reserve the long forms for beginner tutorials only.

### Constants and `iota`

Constants are fixed values determined at compile time. They can be declared singly or in groups. In a group, if the value is omitted, it repeats the expression from the previous line.

```kukicha
const PI = 3.14159
const (
    StatusActive = iota  # 0
    StatusInactive       # 1
    StatusArchived       # 2
)

const (
    FormatJSON string = "json"
    FormatXML          # also string = "json" (repetitions inherit both type and value)
)
```

- `iota` is a special constant that resets to 0 at the start of every `const` block and increments by 1 for every `ConstSpec`.
- Explicit types are optional but can be provided: `const Name Type = Value`.


### Variables and Functions

```kukicha
count := 42           # inferred type
count = 100           # reassignment

var p reference int   # typed zero-value declaration (works locally too)
var xs list of string

func Add(a: int, b: int) int
    return a + b

func Divide(a: int, b: int) int, error
    if b equals 0
        return 0, error "division by zero"
    return a / b, empty

# Default parameter + named argument at call site
func Greet(name: string, greeting: string = "Hello") string
    return "{greeting}, {name}!"

result := Greet("Alice", greeting: "Hi")
files.Copy(from: src, to: dst)

# Optional `:` between param name and type — beginner-friendly synonym
func triage(issue: Issue) Verdict
    return Verdict{}
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

# Defined named type (distinct from base — needs explicit conversion: UserID(42))
type UserID int
type Status string

# Function type alias
type Handler func(context.Context, string) (string, error)

# Transparent type alias (type X = Y — identical types, cross-package assertions work)
type TextContent = mcp.TextContent

# Use transparent aliases to tame long multi-token types in signatures.
# Rule of thumb: alias if the type repeats 3+ times in a file or pushes
# a signature past ~100 columns.
type UserMap = map of string to reference User

func MergeUsers(primary: UserMap, secondary: UserMap, overrides: list of UserMap) UserMap
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

- Underlying type (int or string) inferred from values; all must match
- Compiler warns on missing cases unless `default` present
- Integer enums warn if no case has value 0
- Auto-generated `String()` method

### String-Backed Enums (`enum Name: string`)

For closed sets of string values (CLI flags, config keys, status codes from external systems), declare the raw type explicitly. The compiler generates both `String()` (returning the raw value, not the case name) and a package-level `Parse<Name>` helper that returns `(<Name>, bool)`.

```kukicha
enum Bump: string
    Patch = "patch"
    Minor = "minor"
    Major = "major"

# Parse at the boundary — typos get rejected here, not 50 lines downstream.
raw := cli.GetString(args, "bump")
b, ok := ParseBump(raw)
if not ok
    cli.Fatal("invalid --bump value '{raw}'")

# Downstream code now takes a typed value, not a stringly-typed one.
func nextTag(current: string, bump: Bump) string
    return semver.Bump(current, bump.String())
```

- Use this shape when you'd otherwise hand-write a `stringToFoo(s) int` returning a `-1` sentinel: the typed `(Bump, bool)` return forces callers to check.
- Raw values must be unique; duplicates are a semantic error.
- For values persisted to a database as integers, use a plain integer enum instead: string-backed enums change the underlying Go type to `string`.

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
func area(s: Shape) float64
    switch s as v
        when Circle
            return 3.14159 * v.radius * v.radius
        when Rectangle
            return v.width * v.height
        when Point
            return 0.0

# Multiple variants can share a body
func isZero(s: Shape) bool
    switch s as v
        when Point
            return true
        when Circle, Rectangle
            return false

# Single-case check with binding
if s is Circle as c
    return 3.14159 * c.radius * c.radius
```

- Cannot mix value cases (`= literal`) and variant cases in the same enum
- `is` for bool checks; `is CaseName as v` binds in `if` blocks (top-level condition only)

### Methods

```kukicha
func Display on todo: Todo string
    return "{todo.id}: {todo.title}"

func SetDone on todo: reference Todo       # pointer receiver
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
riskyOp()              onerr discard                        # ignore (warns; test code only)
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

# Block form with `fallback` — run side effects AND supply a default
setting := loadConfig(path) onerr as e
    print("loadConfig failed: {e} — using default")
    fallback "default-config"

# Multi-value fallback: one expression per LHS slot
x, y := loadCoords() onerr
    print("coords lookup failed; using origin")
    fallback 0, 0
```

`fallback EXPR[, EXPR...]` is a terminator for the `onerr` block (like
`return`/`panic`/`continue`/`break`). It must be the last statement in the
handler, and the expression count must match the LHS slot count. Use it when
you need both side effects (logging, metrics) AND a default value.

### Pipes

```kukicha
result := data |> parse() |> transform()

# _ placeholder for non-first argument
todo |> json.Write(w, _)   # → json.Write(w, todo)

# `_` is reserved for this purpose and as the blank assignment target.
# Reading it as a value (`fmt.Println(_)`, `x := _ + 1`) is a compile error.

# Bare identifier as target
data |> print                     # → fmt.Println(data)

# Pipeline-level onerr — catches errors from any step
resp := fetch.Get(url) |> fetch.CheckStatus() onerr panic "{error}"
items := fetch.Json of list of Repo from resp onerr panic "{error}"

# Piped switch
user.Role |> switch
    when "admin"
        grantAccess()
    default
        checkPermissions()

# Piped switch on a variant enum — exhaustiveness-checked
shape |> switch as v
    when Circle
        return v.radius * v.radius
    when Square
        return v.side * v.side

# Tee a pipe value — `|> also as name` binds the upstream value into the
# enclosing scope and passes it through unchanged. Valid only when the
# pipe is the RHS of `:=` / `=` or a bare expression statement.
n := 5
    |> double()
    |> also as ten
    |> double()
# ten == 10, n == 20

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
    default
        print("Unknown: {command}")

# Bare switch (condition-based)
switch
    when stars >= 1000
        print("popular")
    default
        print("new")

# Type switch
switch event as e
    when string
        print(e)
    when reference TaskEvent
        print(e.Status)

# `where` guard on a `when` clause — predicate on the matched value.
# A guarded case does NOT cover its variant for exhaustiveness; add an
# unguarded `when X` fallback (or `default`).
switch shape as s
    when Circle where s.radius > 10.0
        return "big circle"
    when Circle
        return "small circle"
    when Square
        return "square"

# Active-pattern predicate — `when matches Fn` calls Fn(binding) and
# takes the arm when it returns true. Binding keeps the switched
# expression's static type. Like guarded cases, matcher cases don't
# satisfy exhaustiveness on their own.
switch shape as v
    when matches isBig
        return "big shape"
    when Circle
        return "small circle"
    when Square
        return "small square"
```

### Lambdas

Parameter types are inferred from context; explicit annotations are optional.

```kukicha
repos   |> slice.Filter(r => r.stars > 100)     # inferred type
entries |> sort.ByKey(e => e.name)
repos   |> sort.By((a, b) => a.stars < b.stars)  # two params

# Block lambda (multi-statement)
repos |> slice.Filter(r =>
    name := r.name |> strpkg.ToLower()
    return name |> strpkg.Contains("go")
)

# Explicit return types (optional)
# Single return:
summarizer := (name: string, age: int) list of string =>
    return list of string{"Name: {name}", "Age: {age}"}

# Multi-return:
divider := (a, b float64) (float64, error) =>
    if b equals 0 then return 0, error "div zero"
    return a/b, empty


# Block lambdas may contain pipe chains and onerr:
db.Transaction(pool, (tx) =>
    db.TxExec(tx, "UPDATE accounts SET balance = balance - $1 WHERE id = $2", amt, from) onerr return
    db.TxExec(tx, "UPDATE accounts SET balance = balance + $1 WHERE id = $2", amt, to)   onerr return
    return empty
) onerr panic "transfer failed: {error}"

# Cross-package named types infer from the callback signature — no helper func needed:
retry.DoCtx(ctx, cfg, (h) =>            # h is ctxpkg.Handle, inferred
    _, err := fetch.GetCtx(h, url)
    return err
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
func Sum(many numbers: int) int
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
    default
        print("nothing ready")

# Arm bodies may be empty — omit the indented block:
select
    when send true to ch
    default
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
import "stdlib/http"      as httphelper # clashes with 'net/http'

import "github.com/jackc/pgx/v5" as pgx  # external package
```

Always use these aliases when the package name clashes — collisions cause compile errors.

### Commands

```bash
kukicha init [module]          # init project (go mod init + extract stdlib)
kukicha check file.kuki        # validate syntax
kukicha check --json file.kuki # JSON diagnostics
kukicha run file.kuki          # transpile + compile + run
kukicha run --json file.kuki   # JSON compile errors (program output unchanged on success)
kukicha build file.kuki        # compile to binary
kukicha build myapp/           # build directory
kukicha build --wasm file.kuki # WebAssembly output
kukicha build --json file.kuki # JSON build result
kukicha fmt -w file.kuki       # format in place
kukicha fmt --check dir/       # check formatting (CI / pre-commit gate)
kukicha fmt --check --json dir/ # JSON array of unformatted file paths
kukicha brew file.kuki         # convert .kuki to standalone Go
kukicha pack skill.kuki        # package skill with SKILL.md + binary
kukicha context myapp/         # project metadata as JSON (agents, IDEs, CI)
kukicha audit                  # vulnerability check
```

Run `kukicha fmt -w` before committing; CI should run `kukicha fmt --check`.

`kukicha context <file|dir>` emits a JSON snapshot for agents and CI: top-level decls only (methods, fields, enum cases, interface methods are excluded to keep the shape flat):

```json
{
  "kukicha_version": "0.6.4",
  "petiole": "myapp",
  "is_directory": true,
  "files": ["main.kuki", "lib.kuki"],
  "entry_point": "main.kuki",
  "imports": [{"path": "stdlib/slice", "alias": ""}],
  "functions": ["Hello", "main"],
  "types": ["User"],
  "enums": ["Status"],
  "commands": {"check": "...", "build": "...", "run": "..."}
}
```

`entry_point` is omitted for library projects or when multiple `func main()` declarations are found across files. Names are deduplicated across files and sorted.

---

### Stdlib Packages

Browse `.kukicha/stdlib/` for full API details. Key functions listed below.

#### Collections & Strings

**slice**: `Filter`, `Reject`, `Partition`, `Map`, `GroupBy`, `Sort`, `SortBy`, `First`, `Last`, `Contains`, `Unique`, `Chunk`, `Find`, `FindOr`, `Get`, `GetOr`, `FirstOr`, `LastOr`, `Pop`, `Shift`, `Reverse`, `Concat`, `IndexOf`, `IsEmpty`, `Sum`, `Min`, `Max`, `Average`

```kukicha
active := slice.Filter(items, x => x.active)
live   := slice.Reject(items, x => x.deleted)            # inverse of Filter
healthy, unhealthy := slice.Partition(items, x => x.ok)  # single pass, both halves
names  := slice.Map(items, x => x.name)
first  := slice.FirstOr(items, defaultVal)
total  := slice.Sum(scores)                              # ordered: ints, floats, strings
hi, _  := slice.Max(scores)                              # error on empty; Min/Average mirror this
```

**maps**: `Keys`, `Values`, `Contains`, `Has`, `Merge`, `Filter`, `MapValues`, `Pick`, `Omit`, `SortedKeys`, `GetOr`

**set**: `From`, `Add`, `AddIn`, `Remove`, `Contains`, `Union`, `Intersect`, `Difference`, `IsSubset`, `Equal`, `ToSlice`

**sort**: `Strings`, `Ints`, `Float64s`, `By`, `ByKey`, `Reverse`

```kukicha
sorted := repos |> sort.ByKey(r => r.name)
```

**string** (as `strpkg`): `Split`, `Join`, `ToUpper`, `ToLower`, `Contains`, `HasPrefix`, `HasSuffix`, `Replace`, `ReplaceAll`, `Trim`, `TrimSpace`, `Fields`, `Lines`, `PadRight`, `PadLeft`, `IsEmpty`, `IsBlank`, `OrDefault`

**regex**: `Match`, `Find`, `FindAll`, `FindGroups`, `Replace`, `Split`, `MustCompile` + compiled variants

**iterator**: Lazy iteration (Go 1.23 iter.Seq): `Values`, `Filter`, `Map`, `FlatMap`, `Take`, `Skip`, `Enumerate`, `Chunk`, `Zip`, `Reduce`, `Collect`, `Any`, `All`, `Find`

```kukicha
names := repos
    |> iterator.Values()
    |> iterator.Filter((r) => r.Stars > 100)
    |> iterator.Map((r) => r.Name)
    |> iterator.Take(5)
    |> iterator.Collect()
```

**cast**: `SmartInt`, `SmartFloat64`, `SmartBool`, `SmartString`

#### Data & Encoding

**json** (as `jsonpkg`): `Bytes`, `PrettyBytes`, `ParseInto`, `ParseStringInto`, `Write`, `ReadInto`, `Read`, `Parse`, `ParseString`, `Pretty`

**parse**: `JSON of T from text`, `YAML of T from text`, `Form of T from values`, `Env of T from prefix` (parse + auto-Validate, return `(T, list of validate.FieldError)`); `JSONLines`, `CSV`, `CSVRecords`, `Lines`, `Duration`, `URL`, `Query`

**encoding**: `Base64Encode`, `Base64Decode`, `HexEncode`, `HexDecode`

**template**: Convenience layer over `text/template` and `html/template`. One-shots: `Render`, `HTML`. Parsed-once: `Compile`, `CompileHTML` returning `Template` / `HTMLTemplate` with a `Render(data)` method.

**markdown**: CommonMark → HTML rendering, backed by yuin/goldmark. `ToHTML(md)` (CommonMark + GFM tables, strikethrough, task lists, autolink; raw HTML escaped), `ToHTMLWith(md, Options{Tables, Strikethrough, TaskList, Footnotes, DefinitionList, AutoLink, HardWrap, AutoHeadingID, AllowRawHTML})`. Raw HTML is escaped by default; pass the output through `http.SafeHTML` if you're rendering untrusted Markdown to an HTTP response.

#### I/O & Files

**files**: `Read`, `ReadString`, `Write`, `Append`, `Exists`, `IsDir`, `Copy`, `Move`, `Delete`, `List`, `ListRecursive`, `MkDirAll`, `TempFile`, `TempDir`, `Join`, `Watch`

```kukicha
data := files.Read("config.json") onerr panic "{error}"
files.Copy(from: src, to: dst) onerr panic "{error}"
```

**archive**: Zip and tar.gz archives, safe-by-default extraction (rejects "zip slip" paths): `Extract`, `List`, `ReadEntry`, `WriteZip`, `WriteTarGz`

```kukicha
archive.Extract("release.tar.gz", "/tmp/release") onerr panic "{error}"
entries := archive.List("release.zip") onerr return
data := archive.ReadEntry("release.zip", "config.yaml") onerr return
archive.WriteTarGz("release.tar.gz", "build/") onerr return
```

**sandbox**: Filesystem sandboxing (use in HTTP handlers): `New`, `Read`, `Write`, `List`, `Exists`

```kukicha
box := sandbox.New("/var/data") onerr return
content := sandbox.Read(box, userPath) onerr return   # can't escape root
```

**shell**: `Run` (fixed literals only), `Output` (variable args), `Lines` (stdout split into lines, trailing empty stripped), `Check` (run for side effect — nil or error wrapping stderr), `Capture` (returns stdout+stderr regardless of exit code), `New`/`Dir`/`Env`/`Execute` (builder), `Stdin`/`StdinBytes` (feed bytes to subprocess stdin then EOF), `Require` (stdout or err-wrapping-stderr; pairs with `Execute` in pipes)

```kukicha
diff  := shell.Run("git diff --staged") onerr panic "{error}"
out   := shell.Output("git", "log", "--oneline", branch) onerr panic "{error}"
files := shell.Lines("git", "ls-files") onerr return
tests := shell.New("go", "test", "./...") |> shell.Execute() |> shell.Require() onerr return

# Run for its side effect only — discard output, return nil or error
shell.Check("kukicha", "fmt", "-w", ".") onerr panic "{error}"
shell.New("go", "generate", "./...") |> .Check() onerr return

# Capture both stdout and stderr regardless of exit code
stdout, stderr, err := shell.Capture("go", "build", "./...")
stdout, stderr, err := shell.New("cmd") |> .Stdin(input) |> .Capture()

# Pipe input into a subprocess (signals EOF after writing the bytes)
reply := shell.New("claude", "--print")
    |> .Stdin(prompt)
    |> .Output() onerr return
```

When to use each:
- `Output` / `Lines`: when you need stdout, want an error on non-zero exit
- `Check`: when you only care about success or failure, not the output
- `Capture`: when you need both stdout **and** stderr (e.g. to display separately, or log warnings on success)

#### HTTP & Networking

**fetch**: HTTP client with builder, auth, retry, SSRF protection

```kukicha
# Typed JSON decode — explicit type argument
repos := fetch.GetJson of list of Repo from url onerr panic "{error}"

# Or split status check and decode:
resp := fetch.Get(url) |> fetch.CheckStatus() onerr panic "{error}"
repos := fetch.Json of list of Repo from resp onerr panic "{error}"

# Builder: auth, timeout, retry
resp := fetch.New(url)
    |> fetch.BearerAuth(token)
    |> fetch.Retry(3, 500)
    |> fetch.Do() onerr panic "{error}"
```

Key: `Get`, `SafeGet` (SSRF-safe), `Post`, `Json`, `Text`, `Bytes`, `CheckStatus`, `URLTemplate`, `URLWithQuery`, `New`/`NewExternal` (SSRF-safe builder)/`BearerAuth`/`Timeout`/`Retry`/`MaxBodySize`/`Do`, `DownloadTo`

**http** (as `httphelper`): Response helpers + security

```kukicha
httphelper.JSON(w, data)                                       # 200 OK
httphelper.JSONCreated(w, data)                                 # 201
httphelper.JSONNotFound(w, "not found")                         # 404
httphelper.JSONBadRequest(w, "bad input")                       # 400
httphelper.ReadJSONLimit(r, 1<<20, reference of input) onerr return
httphelper.SafeRedirect(w, r, url, "myapp.com") onerr return
httphelper.SetSecureHeaders(w)
```

**html**: Component-style rendering with auto-escaping: `Render`, `Escape`, `Attr`, `Embed`, `WriteTo`, `Join`, `Map`, `When`, `WhenElse`

```kukicha
page := html.Render("<h1>{html.Escape(title)}</h1>")
html.WriteTo(w, page) onerr discard
```

**netguard**: SSRF protection: `NewSSRFGuard`, `NewAllow`, `NewBlock`, `Check`, `HTTPClient`, `HTTPTransport`. For IP/CIDR parsing, use Go's `net` package directly.

#### CLI & System

**cli**: Argument parsing: `New`, `Version` (enables `--version`), `Description`, `AddFlag`, `Action`, `Run`, `NewCommand`, `WithCommands`, `GlobalFlag`, `BoolGlobalFlag`, `IntGlobalFlag`, `GetString`, `GetBool`, `GetInt`, `GetRest`, `ParseArgs`, `Fatal`, `Error`. Build each subcommand with `cli.NewCommand(name, desc) |> .BoolFlag(...) |> .Action(...)`, then attach via `cli.WithCommands(cmd1, cmd2, ...)`.

Use **typed flag constructors** (`BoolFlag`/`IntFlag`/`StringFlag`) instead of the generic `Flag(name, desc, "default")` whenever the type is known: the compiler tracks the type, enables `--flag=value` form, and prevents misparse of the next arg as the flag value.

```kukicha
# Flat app (no subcommands)
app := cli.New("myapp")
    |> cli.Version("0.1.0")          # enables --version
    |> cli.AddFlag("port", "Port", "8080")
    |> cli.Action(run)
cli.Run(app) onerr panic "{error}"

# Subcommands with typed flags and short aliases
listCmd := cli.NewCommand("list", "List items")
    |> .BoolFlag("csv", "CSV output", false)
    |> .IntFlag("limit", "Max results", 20)
    |> .StringFlag("filter", "Filter by language", "")
    |> .Short("filter", "f")
    |> .Action(doList)

releaseCmd := cli.NewCommand("release", "Cut a release")
    |> .BoolFlag("dry-run", "Show what would happen", false)
    |> .BoolFlag("draft", "Create draft release", true)
    |> .Short("dry-run", "n")
    |> .Action(doRelease)

cli.New("myapp")
    |> cli.IntGlobalFlag("limit", "Max results", 10)
    |> cli.BoolGlobalFlag("json", "JSON output", false)
    |> cli.WithCommands(listCmd, releaseCmd)
    |> cli.Run() onerr cli.Fatal("{error}")

# RestArg — collect overflow positionals into a named slot
buildCmd := cli.NewCommand("build", "Build targets")
    |> .RestArg("targets")
    |> .Action(doBuild)

func doBuild(args cli.Args)
    targets := cli.GetRest(args, "targets")  # list of string

# ParseArgs — unit-test a CLI app without patching os.Args
app := cli.New("tool") |> .BoolFlag("verbose", "Verbose", false) |> cli.Action(doRun)
args, err := cli.ParseArgs(app, list of string{"tool", "--verbose"})
```

**input**: `ReadLine`, `Prompt`, `Confirm`, `Choose`; `Form` builder: `NewForm`, `Text`, `Confirm`, `Choose`, `Validate`, `Default`, `Run`, `String`, `Bool`

```kukicha
form := input.NewForm()
    |> .Text("name", "Your name?")
    |> .Default("name", "anonymous")           # substituted on blank-line submit
    |> .Choose("env", "Environment?", list of string{"dev", "prod"})
    |> .Confirm("ok", "Proceed?")
form.Run() onerr panic "{error}"
name := form.String("name")
```

**table**: Terminal tables: `New`, `AddRow`, `Print`, `PrintWithStyle` (`"plain"`, `"box"`, `"markdown"`), `ToString`, `ToStringWithStyle`. Width math is ANSI-aware via `term.VisibleWidth`, so colored cells align with plain neighbors.

**color**: ANSI terminal styling. Package-level funcs delegate to a default styler bound to `os.Stdout`; use `NewStyler(w)` for an explicit writer (e.g., `os.Stderr`). Capability detection delegates to `stdlib/term`.

Funcs: `NewStyler`, `Enabled`, `SetEnabled`, `Bold`, `Dim`, `Italic`, `Underline`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `Gray`, `BrightRed`, `BrightGreen`, `BrightYellow`, `BrightBlue`, `BrightMagenta`, `BrightCyan`, `BrightWhite`, `Error` (bold bright red). Each is also a method on `Styler`.

```kukicha
print(color.Bold("Title"))
print(color.Error("fatal: disk full"))
print(color.Green("All tests passed"))

# Bind to stderr so stdout stays pipe-friendly
errStyle := color.NewStyler(os.Stderr)
fmt.Fprintln(os.Stderr, errStyle.Error("boom"))
```

**term**: Single source of truth for tty / color / width detection. Funcs: `IsTTY(f)`, `ColorEnabled()`, `ColorEnabledFor(f)`, `SetColorEnabled(bool)`, `ResetColorOverride()`, `Width()`, `VisibleWidth(s)` (ANSI-CSI-aware), `PadRightVisible(s, n)`. Use this from any tty-aware stdlib package instead of rolling per-package globals.

**log**: Leveled structured logger (Text + JSON formats). `New(w)` for a `Logger` value; package-level funcs bind to `os.Stderr`. Methods/funcs: `Debug`, `Info`, `Warn`, `Error`, `Fatal`. Globals: `SetLevel(level)`, `SetFormat(format)`. Color via `color.NewStyler` so log honors term overrides.

```kukicha
log.SetLevel(log.LevelDebug)
log.Info("server starting", "port", 8080)
log.Error("query failed", "err", error, "user", uid)

l := log.New(os.Stdout)
l.Warn("cache miss", "key", k)
```

**env**: Typed env vars with onerr: `Get`, `GetOr`, `GetInt`, `GetBool`, `Set`, `All`

**must**: Panic-on-error startup: `Env`, `EnvOr`, `EnvInt`, `EnvIntOr`, `True`, `NotEmpty`

```kukicha
apiKey := must.Env("API_KEY")
port   := must.EnvIntOr("PORT", 8080)
debug  := env.GetBool("DEBUG") onerr false
```

#### Concurrency & Resilience

**concurrent**: `Parallel`, `ParallelWithLimit`, `Map`, `MapWithLimit`, `Go`

```kukicha
results := concurrent.Map(urls, url => check(url))
results := concurrent.MapWithLimit(repos, 4, r => fetchDetails(r))
```

**ctx** (as `ctxpkg`): `Background`, `WithTimeout`, `Cancel`, `Done`, `Value`

**retry**: `New`, `Attempts`, `Delay`, `Linear`, `Sleep`

**datetime**: `Format`, `Parse`, `Now`, `AddDays`, `Seconds`, `Sleep`; Constants: `ISO8601`, `RFC3339`, `Date`, `Time`

#### Data & Storage

**db** (alias `dbpkg` when local `db` variable exists): SQL with struct scanning: `Open`, `Close`, `Query`, `QueryRow`, `Exec`, `ScanAll`, `ScanOne`, `ScanRow`, `Transaction`, `Count`, `Exists`

```kukicha
pool := db.Open("postgres", connStr) onerr panic "{error}"
defer db.Close(pool)
users := db.Query(pool, "SELECT id, name FROM users WHERE active = $1", true)
    |> db.ScanAll of User onerr panic "{error}"
```

**sqlite**: SQLite convenience (WAL, foreign keys, busy timeout by default): `Open`, `OpenMemory`, `OpenWith`, `Pragma`, `Tables`, `TableExists`, `BatchExec`, `Backup`, `Dump`, `CreateFunction`, `CreateFunctionFloat`, `CreateFunctionInt`, `CreateFunctionBool`, `CreateBlobFunction`, `CreateBlobFunctionFloat`

```kukicha
pool := sqlite.Open("/tmp/app.db") onerr panic "{error}"
defer db.Close(pool)
# All queries use stdlib/db — same Query/Exec/ScanAll API
```

#### Security & Crypto

**crypto**: `SHA256`, `HMAC`, `RandomToken`, `RandomBytes`, `Equal` (constant-time)

**validate**: pipe-style: `Email`, `URL`, `NotEmpty`, `MinLength`, `MaxLength`, `InRange`, `Matches`, `NoHTML`, `SafeFilename`. Tag-driven: attach `# kuki:validate "rule[,rule…]"` above struct fields; the compiler emits `Validate()` returning `list of FieldError`. Rules: `nonempty`, `nonzero`, `min=N`, `max=N`, `len=N`, `email`, `url`, `regex=PAT`, `oneof=a|b|c`. Pair with `parse.JSON of T from body` for one-call parse-and-validate. `validate.RunTags(v)` runs the generated method even when the user defines their own `Validate`.

**random**: `String`, `Alphanumeric`, `Int`, `Float`

**errors** (as `errs`): `Wrap`, `Opaque`, `Is`, `New`, `Join`, `NewPublic`, `Public`

#### DevOps & Infrastructure

**git**: Git/GitHub via `gh`: `ListTags`, `TagExists`, `DefaultBranch`, `CreateRelease`, `PreviewRelease`

**semver**: `Parse`, `Bump`, `Format`, `Valid`, `Compare`, `Highest`

**obs**: Structured logging: `New`, `Component`, `Info`, `Warn`, `Error`, `Start`, `Stop`

#### AI & Agents

**llm**: Shared schema utilities: `Prop`, `Schema`, `Required` (for building tool parameter schemas)

**llm/chat**: Chat Completions API (OpenAI-compatible): `New`/`Ask`/`Send`/`SendRaw`/`Complete`/`CompleteWithSystem`; `System`/`User`/`Assistant`; `Temperature`/`MaxTokens`/`Stream`/`StreamEvents`/`Retry`/`WithContext`; `AddTool`/`JSONMode`; `FromCompletion`/`ExecuteToolCalls`; `GetText`/`GetToolCalls`/`HasToolCalls`

**llm/responses**: OpenResponses API: `New`/`Ask`/`Send`/`AskRaw`/`SendRaw`/`Respond`/`RespondWithInstructions`; `Instructions`/`User`/`System`/`Developer`/`PreviousResponse`; `Temperature`/`MaxOutputTokens`/`Stream`/`StreamEvents`/`Retry`/`WithContext`; `AddTool`/`JSONMode`/`JSONSchema`/`Store`; `FromResponse`/`ExecuteFunctionCalls`/`FunctionCallOutput`; `GetText`/`GetFunctionCalls`/`HasFunctionCalls`

**llm/anthropic**: Anthropic Messages API: `New`/`Ask`/`Send`/`AskRaw`/`SendRaw`/`Complete`/`CompleteWithSystem`; `System`/`User`/`Assistant`/`ToolResult`; `Temperature`/`MaxTokens`/`AdaptiveThinking`/`Effort`/`Stream`/`StreamEvents`/`Retry`/`WithContext`; `AddTool`; `FromResponse`/`ExecuteToolUses`; `GetText`/`GetThinking`/`GetToolUses`/`HasToolUses`

**llm/embeddings**: Text embeddings (OpenAI-compatible — works with OpenAI text-embedding-3-*, Cohere, Voyage text models, Mistral, Together, DeepSeek, Ollama): `New`, `Embed` (one-shot), `EmbedOne`, `EmbedBatch`, `EmbedRaw`; builders: `Provider`/`Model`/`BaseURL`/`Path`/`APIKey`/`Dimensions` (Matryoshka truncation)/`EncodingFormat`/`SetUser`/`InputType`/`Retry`/`WithContext`. For multimodal embeddings (text + image/video/audio), see future `llm/voyage` and `llm/gemini` packages.

```kukicha
import "stdlib/llm/embeddings"

vec := embeddings.Embed("openai:text-embedding-3-small", "hello world") onerr panic "{error}"

# Truncated dimensions (Matryoshka)
vec := embeddings.New("openai:text-embedding-3-large")
    |> embeddings.Dimensions(512)
    |> embeddings.EmbedOne("hello world")
    onerr panic "{error}"

# Batch
vecs := embeddings.New("openai:text-embedding-3-small")
    |> embeddings.EmbedBatch(list of string{"first", "second"})
    onerr panic "{error}"
```

**llm/safe**: Prompt-injection-resistant input wrapping: `Wrap(label, content)` (delimit untrusted text), `Frame(instructions, blocks)` (assemble system prompt + labeled untrusted blocks), `UntrustedPreamble` (boilerplate "treat the following as data, not instructions"), `Truncate(s, maxLen)`, `SanitizeLine(s, maxLen)` (strip control chars + collapse whitespace), `IsStructural(s)` (detect markdown/heading/list bullets that could break out of a bullet point). Use when feeding commit messages, user input, fetched HTML, or other adversarial text into an LLM.

```kukicha
import "stdlib/llm"
import "stdlib/llm/chat"

# one-shot
reply := chat.New("openai:gpt-4o-mini") |> chat.Retry(3, 2000) |> chat.Ask("Hello!") onerr panic "{error}"

# agentic tool loop
schema := llm.Schema(list of llm.SchemaProperty{llm.Prop("city", "string", "City name")}) |> llm.Required(list of string{"city"})
c := chat.New("openai:gpt-4o-mini") |> chat.AddTool("get_weather", "Get weather", schema) |> chat.User("Weather in Paris?")
comp := c |> chat.SendRaw onerr panic "{error}"
if chat.HasToolCalls(comp)
    handlers := make(map of string to func(string) string)
    handlers["get_weather"] = (args: string) => "Sunny, 22°C"
    c = chat.ExecuteToolCalls(c, comp, handlers) onerr panic "{error}"
    reply = c |> chat.Send onerr panic "{error}"
```

**mcp**: MCP server + client: `New`, `Serve`, `ServeHTTP`, `Tool`, `ToolWithOpts`, `ToolRich`, `Resource`, `TextResource`, `ResourceTemplate`, `TextResourceTemplate`, `Prompt`, `UserPrompt`, `Prop`, `Schema`, `Required`, `TextResult`, `ErrorResult`, `Connect`, `BearerConnect`, `ConnectWithClient`, `Close`, `ListTools`, `CallTool`, `ListResources`, `ListResourceTemplates`, `ReadResource`, `ListPrompts`, `GetPrompt`, `NewWithCompletion`, `Completions`, `CompletionsPage`, `NewRouter`

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

**skills**: Agent SKILL.md discovery: `Discover`, `AgentSkills`, `ClaudeSkills` *(deprecated — copy the package or call `filepath.Walk` directly)*

#### External Packages (separate modules)

These packages require adding a separate Go module to your project: they are not bundled with the Kukicha compiler.

**game** (WASM-only): 2D game lib: `Window`, `Run`, `DrawRect`, `DrawCircle`, `DrawText`, `IsKeyDown`, `MousePosition`
Module: `github.com/kukichalang/game` — add with `go get github.com/kukichalang/game`

**infer** / **ort** / **webinfer**: ML inference
Module: `github.com/kukichalang/infer` — add with `go get github.com/kukichalang/infer`

---

**Built-in packages:** `archive`, `cast`, `cli`, `concurrent`, `crypto`, `ctx`, `datetime`, `db`, `encoding`, `env`, `errors`, `fetch`, `files`, `git`, `html`, `http`, `input`, `iterator`, `json`, `llm`, `log`, `maps`, `mcp`, `must`, `net`, `netguard`, `obs`, `parse`, `random`, `regex`, `retry`, `sandbox`, `semver`, `set`, `shell`, `slice`, `sort`, `sqlite`, `string`, `table`, `template`, `term`, `test`, `validate`

**External packages** (separate module required): `game`, `infer`, `ort`, `webinfer`

---

### Security — Compiler-Enforced Checks

The compiler **rejects** these patterns in HTTP handlers (functions with `http.ResponseWriter`):

| Pattern | Fix |
|---------|-----|
| `httphelper.HTML(w, nonLiteral)` | `httphelper.SafeHTML(w, content)` |
| `fetch.Get(url)` in handler | `fetch.SafeGet(url)` (or `fetch.NewExternal(url) \|> ... \|> Do()` for builder) |
| `files.Read(path)` in handler | `sandbox.New(root)` + `sandbox.Read(box, path)` |
| `shell.Run("cmd {var}")` | `shell.Output("cmd", arg)` |
| `httphelper.Redirect(w, r, nonLiteral)` | `httphelper.SafeRedirect(w, r, url, "host")` |
| `html.Render("<script>...")` | Static `.js` file with `<script src="...">` |
| `regex.Match(userPattern, ...)` (non-literal pattern) | `regex.MatchSafe(pattern, text)` returns error, or hoist with `regex.MustCompile` at init + `regex.MatchCompiled` |

`http.SafeRedirect` rejects non-`http`/`https` schemes (e.g. `javascript:`, `data:`, `file:`), protocol-relative `//host`, and bare relative paths: only allow-listed hosts on absolute http(s) URLs are permitted.

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

`kukicha pack weather.kuki` produces an [agentskills.io](https://agentskills.io/specification)-compliant directory:

```
skills/weather-service/
├── SKILL.md                    # frontmatter (name, description, metadata) + markdown body
└── scripts/
    └── weather-service.kuki    # source copy — no binary compilation
```

Agents invoke the skill by running the source at call time (no cross-compilation):

```bash
kukicha run scripts/weather-service.kuki <args>
```

Pass a directory to pack multi-file skills; all `.kuki` files (except tests) are copied under `scripts/<name>/`. Discover at runtime (`stdlib/skills` is deprecated; copy the package or call `filepath.Walk` directly):

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

type TakeCase
    name    string
    n       int
    wantLen int

func TestTake(t: reference testing.T)
    items := list of string{"a", "b", "c", "d", "e"}
    cases := list of TakeCase{
        TakeCase{name: "3 elements", n: 3, wantLen: 3},
        TakeCase{name: "n > length", n: 10, wantLen: 5},
    }
    for tc in cases
        t.Run(tc.name, (t: reference testing.T) =>
            result := slice.Take(items, tc.n)
            test.AssertEqual(t, len(result), tc.wantLen)
        )
```

Assertions: `AssertEqual`, `AssertNotEqual`, `AssertTrue`, `AssertFalse`, `AssertNoError`, `AssertError`, `AssertNotEmpty`, `AssertNil`, `AssertNotNil`.

---

### Pitfalls

**WaitGroups: always `defer wg.Done()` as first goroutine statement.** Explicit `wg.Done()` at the end is skipped if the task panics, hanging `wg.Wait()` forever.

**Context cancel: defer in the function that uses the resource, not the one that creates it:**

```kukicha
# WRONG — cancel fires when buildCmd returns, context is dead before use
func buildCmd() reference exec.Cmd
    h := ctxpkg.WithTimeout(ctxpkg.Background(), 30 * time.Second)
    defer h.Cancel()
    return exec.CommandContext(h.Ctx, name, many args)

# CORRECT — defer in Execute, which owns the resource's lifetime
func Execute() Result
    h := ctxpkg.WithTimeout(ctxpkg.Background(), 30 * time.Second)
    defer h.Cancel()     # fires after Run()
    execCmd := exec.CommandContext(h.Ctx, name, many args)
    ...
```

**Cleanup goroutines**: always provide a shutdown path (context or stop channel). Goroutines looping on a ticker leak if there's no stop signal.

**Never use `io.NopCloser` on a live response body**: it silences `Close()`, leaking TCP connections. Wrap with a type that delegates both `Read` and `Close`.


**`in` / `not in` are membership operators**: `x in xs` works on lists (element comparison), maps (key lookup), and strings (substring). For lists with non-comparable element types (slices, maps, funcs as elements), use `slice.Contains` with a custom predicate. `in` also still drives `for` loops.

---

### Troubleshooting

| Error | Fix |
|-------|-----|
| `use {error} not {err} inside onerr` | Change `{err}` to `{error}`, or use `onerr as e` |
| `variable 'x' not used` | Remove the variable, or use it; never use `_ = x` to suppress — remove the dead code instead |
| `function must declare return type` | Add explicit return type: `func F() int` |
| `onerr return requires return type` | Use `onerr discard`, or add return type |
| `SSRF risk` / `path traversal` / `command injection` / `XSS risk` | See Security table above |
| `expected INDENT` | Check 4-space indentation (no tabs) |
| `expected 'when' or 'default'` | Use `when`/`default` |

<!-- kukicha:end -->
