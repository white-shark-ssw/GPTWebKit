# Technical Decisions

This file records durable, evidence-backed technical decisions and rejected routes.

## TD-001 — Enhancer state ownership is centralized by subsystem

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: `ChatGPTEnhancer`
- **Decision**: Keep one constructor (`CEBootstrap`); use `CEConversationContext` for active conversation identity; use `CENetworkObserver` for official-network observation, `CEAPIClient` for enhancer-originated requests, `CECatalog` for conversation catalog state, and `CEEnhancerUI` for host-app UI integration.
- **Evidence**: `ChatGPTEnhancer/ARCHITECTURE.md` and current source tree.
- **Alternatives considered**: Feature-local constructors, independent ID guessing, feature-local UIKit hooks or network request stacks.
- **Rejected / do-not-repeat**: Do not create duplicate state owners merely to make a feature self-contained.
- **Affected modules**: Bootstrap, Core, Network, Storage, UI, Features.
- **Validation level**: Architecture documented + code written; runtime stability varies by candidate.
- **Supersedes**: None.
- **Notes**: Parallel work touching these shared owners requires conflict preflight.

## TD-002 — Sensitive host authentication context is memory-only

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: Enhancer networking
- **Decision**: Authorization/account headers and raw official request templates may be observed/reused in memory but must not be persisted to disk.
- **Evidence**: `ChatGPTEnhancer/README.md`, `ChatGPTEnhancer/ARCHITECTURE.md`.
- **Alternatives considered**: Persisting auth/cookies/request templates for convenience.
- **Rejected / do-not-repeat**: Do not store Authorization, cookies, account IDs or raw request templates as enhancer persistence.
- **Affected modules**: Network, Storage, Diagnostics.
- **Validation level**: Documented contract + current architecture.
- **Supersedes**: None.

## TD-003 — Markdown export uses complete conversation data, not UI rendering

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: Conversation export
- **Decision**: Export should fetch complete conversation JSON by conversation ID and follow `current_node -> parent -> root`, avoiding rendering/loading a conversation UI solely for export and avoiding abandoned edited/regenerated branches.
- **Evidence**: `ChatGPTEnhancer/README.md`, `ChatGPTEnhancer/ARCHITECTURE.md`, `Sources/Export/CEMarkdownExporter.*`.
- **Alternatives considered**: DOM/UI scraping or loading a conversation screen to export it.
- **Rejected / do-not-repeat**: Never load a conversation UI merely to export it.
- **Affected modules**: Export, Network, Features.
- **Validation level**: Code written; candidate-specific runtime verification must be tracked separately.
- **Supersedes**: Older WebView/DOM-oriented export approaches for enhancer work.

## TD-004 — Manual reload is exact-current-conversation only

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: Enhancer manual conversation reload
- **Decision**: Reload only the exact active conversation ID. Retry delivery through the official app's own custom route for the same conversation, and verify success by observing official detail/resume requests. Stop if app state/context changes.
- **Evidence**: Commit `8e520cba370870173a5ef08392636e1ca8036308`; `.github/workflows/build-enhancer.yml` alpha39 comments.
- **Alternatives considered**: History-row/sidebar automation, UIKit pop/push navigation, using another conversation ID, orphaned-conversation fallback.
- **Rejected / do-not-repeat**: Do not use History rows, sidebar automation, UIKit pop/push, or another conversation ID as reload fallback unless a future explicit decision with new runtime evidence supersedes this rule.
- **Affected modules**: `Features/CEManualConversationReload.mm`, Network observer, current conversation context.
- **Validation level**: Code written + CI passed + artifact produced for alpha39; alpha39 runtime/manual result remains Unknown / Unverified in repository evidence.
- **Supersedes**: Older manual reload fallback route.

## Rule

Do not write speculation here as fact. A historical plan is not proof of implementation.
