module owui

go 1.26.4

require (
	github.com/google/jsonschema-go v0.4.3 // indirect
	github.com/segmentio/asm v1.2.1 // indirect
	github.com/segmentio/encoding v0.5.4 // indirect
	github.com/yosida95/uritemplate/v3 v3.0.2 // indirect
	golang.org/x/oauth2 v0.36.0 // indirect
	golang.org/x/sys v0.45.0 // indirect
	golang.org/x/text v0.37.0 // indirect
)

require (
	codeberg.org/kukichalang/kukicha/stdlib v0.52.0
	github.com/modelcontextprotocol/go-sdk v1.6.0 // indirect
	golang.org/x/term v0.43.0 // indirect
)

replace github.com/kukichalang/kukicha/stdlib => ./.kukicha/stdlib

replace codeberg.org/kukichalang/kukicha/stdlib => ./.kukicha/stdlib
