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
- **Validation level**: Code written + CI passed + artifact produced for alpha39; candidate-specific current-identity correctness is tracked separately.
- **Supersedes**: Older manual reload fallback route.

## TD-005 — Enhancer-generated conversation titles are presentation, never identity evidence

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: Enhancer current-conversation UI / identity resolution
- **Decision**: When `CEEnhancerUI` rewrites host-app presentation with a conversation title, mark that label as enhancer-synthetic and exclude its own text/accessibility values from all generic current-conversation evidence paths. Only independent host/catalog evidence may change `CEConversationContext`.
- **Evidence**: alpha41 post-build review found a self-feedback cycle was possible: stale context A could write A's title into project chat B, after which visible-title resolution could read the plugin-generated A title and reinforce A. Alpha42 commits isolate the marked label in `CECore`, `CEContextResolver`, accessibility/touch resolution, and floating visible-title resolution.
- **Alternatives considered**: Let the rewritten header participate in normal visible-title matching; create another header-local current-conversation state owner.
- **Rejected / do-not-repeat**: Do not treat plugin-generated UI text as proof of active conversation identity and do not create a second conversation authority to compensate.
- **Affected modules**: `Core/CECore.*`, `Core/CEContextResolver.mm`, `UI/CEEnhancerUI.mm`.
- **Validation level**: Code written + CI passed + artifact produced. Alpha42 later failed the broader current-identity invariant for a separate network-driven reason; this decision is not itself runtime-proven.
- **Supersedes**: The incomplete alpha41 project-header evidence handling.

## TD-006 — Standalone ChatGPT client uses native iOS presentation, not WebView chat rendering

- **Status**: Confirmed planning direction
- **Date**: 2026-08-25
- **Scope**: `DEV-native-chatgpt-client`
- **Decision**: The new standalone client will render conversation lists, messages, composer, attachments and navigation with native iOS controls. ChatGPT Web / WKWebView is not the primary chat UI and DOM/React virtualization is not the long-conversation architecture. The client will instead use a native networking/protocol adapter against real ChatGPT backend behavior verified from current request evidence.
- **Evidence**: User explicitly reports repeated WebView optimization versions still retain unacceptable long-conversation lag and requests a native client using the Web/backend communication model. Existing repository evidence shows native Foundation networking can consume ChatGPT conversation data without rendering Web UI, but standalone authentication/send/stream behavior remains to be verified separately.
- **Alternatives considered**: Continue tuning WebView DOM virtualization, timers/observers, or use WebView as the main conversation renderer.
- **Rejected / do-not-repeat**: Do not return to WebView/React/DOM chat rendering as the primary architecture merely to preserve existing code. Do not invent private endpoints/auth/stream contracts without real evidence.
- **Affected modules**: New standalone-client track; exact future source modules are not yet selected. Existing `ChatGPTEnhancer` modules remain separate.
- **Validation level**: User requirement + architecture planning only; no product code, CI, artifact or runtime validation.
- **Supersedes**: WebView-first rendering direction for the new client only. It does not alter the current `ChatGPTEnhancer` architecture.
- **Notes**: Whether a browser surface is allowed solely as an authentication bootstrap remains an open design question; this decision only prohibits WebView as the normal chat presentation/runtime.

## TD-007 — Observed conversation network requests are not foreground identity authority

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer current-conversation identity and current-conversation actions
- **Decision**: `CENetworkObserver` remains passive and must not set `CEConversationContext.conversationID` merely because an official request URL contains a conversation ID. Generic `NSURLSessionTask.resume` observation must not set foreground identity either. Pull, reload and current-conversation export must require fresh, unique currently-visible conversation proof at action time; if proof is ambiguous or unavailable, fail closed rather than use an older context ID.
- **Evidence**: Alpha42 real-device testing after extended use showed Pull Latest and Reload crossing conversations. Source inspection found two independent unconditional network writers: `CENetworkObserver.observeRequest:` and `CEContextResolver`'s `NSURLSessionTask.resume` probe. Both could process official background/detail traffic for a non-visible conversation, while Pull and manual Reload consumed the resulting `CEConversationContext` ID. Alpha44 removes both network identity writers and adds visible-proof guards at UI and feature consumer boundaries.
- **Alternatives considered**: Continue treating the most recent observed conversation request as active; retain network writes but add timing/debounce heuristics; add a second “visible ID” cache; allow stale-ID fallback when UI proof fails.
- **Rejected / do-not-repeat**: Do not infer foreground identity from request recency alone. Do not add retry/debounce/watchdog heuristics to mask the ownership error. Do not create a second active-conversation authority. Do not execute a current-conversation action when exact visible identity is unproven.
- **Affected modules**: `Core/CEContextResolver.mm`, `Network/CENetworkObserver.mm`, `UI/CEEnhancerUI.mm`, `Features/CEFeatures.mm`, `Features/CEManualConversationReload.mm`.
- **Validation level**: Root cause supported by source + authoritative alpha42 runtime failure; alpha44 code written + CI passed + artifact produced. Alpha44 runtime/manual validation pending.
- **Supersedes**: The alpha42 behavior where observed conversation requests could directly mutate `CEConversationContext`.

## Rule

Do not write speculation here as fact. A historical plan is not proof of implementation.
