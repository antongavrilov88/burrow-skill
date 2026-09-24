# Contributing

## Branches

| Branch | What it is | Who pushes |
|---|---|---|
| `main` | Released code only. Every commit here is a release (or a hotfix that becomes one). Deploys the landing. | merges from `dev` via PR |
| `dev` | Integration branch. Always installable, may be ahead of the last release. | merges from feature branches via PR |
| `feat/<name>`, `fix/<name>`, `docs/<name>` | One change each, branched from `dev`. | you |
| `hotfix/<name>` | Urgent fix branched from `main`; merged to `main` **and** back into `dev`. | you |

## Release flow

1. Work on `feat/...`, open a PR into `dev`. CI runs syntax checks and a secrets scan.
2. When `dev` is ready for a release, tag a candidate on it: `git tag v0.2.0-rc.1 && git push --tags`. The release workflow publishes a **pre-release** with `burrow-skill.zip` — test-install that zip in Claude.
3. Fix on `dev`, tag `-rc.2` if needed.
4. Open a PR `dev → main`, merge (merge commit, not squash — keep history). Tag `v0.2.0` on `main`, push the tag. The workflow publishes the release; Pages redeploys the landing if `docs/` changed.
5. Add the version to `CHANGELOG.md` before tagging, and bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (CI checks they match).

`rc` is a tag, not a branch: with one maintainer a long-lived `release/*` branch adds ceremony without safety. If a second maintainer joins, add `release/x.y` branches then.

## Versioning

Semantic. The skill's user-facing behaviour is the API: a change to what the installers put on a server, or to the manual steps a person has to do, is at least a minor bump.

## Commit messages

`type(scope): summary` — types `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`. Scope is `skill`, `installer`, `landing`, `repo`.

## Language and wording

`SKILL.md` and `references/*.md` are English instructions. Everything said to the person lives in `references/lang/<xx>.md`; the Russian file and the Russian handout are wording tested with real families — change them only after testing the new wording on a real person, and say so in the PR. New languages: translate `lang/en.md` and `lang/handout-en.md`, keep the section numbers. `skills/burrow/SKILL.md` is generated from the root `SKILL.md` frontmatter; if you change the description, regenerate it (CI fails otherwise).

## Rules the skill itself follows (keep them when you change it)

The list under "Hard rules" in `README.md`. A PR that weakens one of them needs a written reason.
