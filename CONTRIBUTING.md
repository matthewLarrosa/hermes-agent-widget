# Contributing

Use Conventional Commits with required scope:

`type(scope): imperative summary`

Types: feat, fix, test, docs, refactor, chore, ci, build, style, perf.

Examples:
- `feat(widget): add destination selection`
- `fix(routing): reject credential-bearing URLs`
- `test(core): cover launch preference resolution`

Run `swift test`, generate project with `xcodegen generate`, and build both HermesMac and HermesIOS schemes before committing. Never claim unsigned build proves signed widget installation or Terminal handoff.
