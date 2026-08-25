# Current Work — Rules

This is the rolling checkpoint for repository governance, documentation policy, AI instructions and collaboration rules.

## Status

**Active**

- **Task**: Install the repository AI self-start governance package and initialize project documentation from real repository evidence.
- **User intent / acceptance criteria**: Make the uploaded governance package authoritative in `white-shark-ssw/GPTWebKit`; future sessions must self-start from GitHub rules and maintain checkpoints/project docs proactively.
- **Baseline**: `main` at `845a4bc2ebc7560af7a523bdec6c5743e667cccd`; root `AGENTS.md` and `docs/project/` were absent before this task.
- **Evidence / reason**: User explicitly requested governance package installation; package `PROJECT_PROFILE.md` is `Initialization: Pending`; repository scan shows product code lives on feature branches rather than `main`.
- **Files in scope**: `AGENTS.md`, `.github/copilot-instructions.md`, `.github/skills/project-change-review/SKILL.md`, `docs/project/**`, `PROJECT_INSTRUCTIONS_TEMPLATE.txt`.
- **Do-not-touch**: Product source, existing product `README.md`, existing development branches/checkpoints, existing PR #1, build artifacts and workflow behavior.
- **Completed**: Governance package inspected; repository branches/PRs/current enhancer source/build/CI/version evidence scanned; core rule entrypoint files written to `main`.
- **Validation state**: Rule drafted / bootstrap rules committed.
- **Pending**: Re-read `AGENTS.md` then `START_HERE.md` from GitHub; populate initialized project docs; verify final repository contents; reset this checkpoint to Idle.
- **Next exact action**: Re-read the committed repository rules in mandated startup order.
- **Rejected / do-not-repeat**: Do not overwrite the existing project `README.md` with the generic rule-package README. Do not create or activate a development task during this Rules session.
- **Open questions / risks**: `main` is not the current product-code baseline; durable docs must distinguish current enhancer candidate from legacy WebView/native app branches without guessing runtime acceptance.

## Proactive checkpoint rule

The conversation/context limit is unpredictable. Once the rules problem and usable direction are clear, establish an Active checkpoint. Refresh at meaningful rule decisions, permanent-rule edits, PR state changes, or direction changes.

## Completion

When complete, move durable rules to permanent rule files, reset only this file to `Idle`, and do not modify/delete/reset any Active development checkpoint merely to finish rules work.
