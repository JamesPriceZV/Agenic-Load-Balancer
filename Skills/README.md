# Project Skills — Agenic Load-Balancer

Project-local skills for use with Claude. Each skill is a folder with a `SKILL.md` (frontmatter + body) and optional `references/` and `examples/` material the skill loads when needed.

To use a skill, point Claude at the folder. Future sessions can locate this directory via the memory entry `[Project skills](skills_repository.md)`.

## Available skills

- **[foundation-models/](foundation-models/SKILL.md)** — Adding intelligent app features with Apple's Foundation Models framework: guided generation (`@Generable` / `@Guide`), streaming partial output, tool calling via the `Tool` protocol, `SystemLanguageModel` availability gating, and Liquid Glass UI patterns. Adapted from Apple's `FoundationModelsTripPlanner` sample with project-specific Swift 6 / HIG / routing-engine integration notes.

## Adding a new skill

```
Skills/<skill-name>/
├── SKILL.md          # required: frontmatter (name, description) + body
├── references/       # optional: deeper reference docs loaded on demand
│   └── *.md
└── examples/         # optional: copy-pasteable code samples
    └── *.swift
```

Keep `SKILL.md` under ~500 lines. Push detailed material into `references/` files referenced from the body.
