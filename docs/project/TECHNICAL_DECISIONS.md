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
- **Decision**: `CENetworkObserver` remains passive and must not set `CEConversationContext.conversationID` merely because an official request URL contains a conversation ID. Generic `NSURLSessionTask.resume` observation must not set foreground identity either. Pull, reload and current-conversation export must require exact current-conversation proof; stale context fallback is prohibited.
- **Evidence**: Alpha42 real-device testing showed Pull Latest and Reload crossing conversations. Source inspection found two independent unconditional network writers consuming arbitrary official/background conversation traffic.
- **Alternatives considered**: Treat most recent arbitrary request as current; debounce/timing heuristics; second visible-ID cache.
- **Rejected / do-not-repeat**: Do not infer foreground identity from generic request recency. Do not add retry/debounce/watchdog to mask the ownership error. Do not create a second active-conversation authority.
- **Affected modules**: Core, Network, UI, Features.
- **Validation level**: Runtime failure + source evidence.
- **Supersedes**: Alpha42 generic observed-request authority.
- **Notes**: TD-009 narrows this rule with new alpha46 evidence for one specific semantic endpoint/field; it does not restore generic network authority.

## TD-008 — Floating tool availability is separate from conversation identity

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer floating tools / current-conversation UX
- **Decision**: The floating tool button is an application UI entry point, not proof that a conversation ID is known. Its visibility/lifecycle must not depend on `CEConversationContext.conversationID` while that UX exists.
- **Evidence**: Alpha44 removed unsafe network identity writes, after which the button disappeared because visibility was gated by non-empty context. Alpha45 removed only that visibility gate.
- **Alternatives considered**: Restore network-derived identity for presentation; hide tools until identity is known.
- **Rejected / do-not-repeat**: Do not couple UI entry visibility to identity authority.
- **Affected modules**: `UI/CEEnhancerUI.mm`.
- **Validation level**: Runtime failure + source evidence + alpha45 CI/artifact.
- **Supersedes**: Alpha44 ID-gated button lifecycle.

## TD-009 — Conversation identity evidence is semantic/source-aware, not UUID-shape-aware

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer current-conversation identity parsing and action targeting
- **Decision**: A UUID-looking string is not a conversation ID merely because it matches UUID syntax. Identity evidence must come from a semantically proven conversation location/field. Alpha46 proves `POST /backend-api/share/create` request-body `conversation_id` is an exact action-scoped ground-truth oracle, and provides strong evidence that `POST /backend-api/conversation/init` with an explicit body `conversation_id` is a foreground existing-conversation navigation signal. Arbitrary menu/configuration UUIDs must never be promoted to conversation identity.
- **Evidence**: Alpha46 real-device trace contained 13 unique UUID-looking menu/configuration identifiers with **zero intersection** with the 7 real conversation IDs observed in network traffic. Current `CEExtractConversationIDFromString(...)` uses a generic UUID regex, so the diagnostic logger mislabeled those structural UUIDs as `conversationID=...`, demonstrating the parser's context-free weakness. The same trace captured 8 Share-create requests across 6 unique chats; each carried explicit body `conversation_id`, including two same-title `测试会话` chats with different IDs. For 7/7 Share events with a preceding explicit `conversation/init` body ID, the latest explicit init ID matched Share exactly. Cold relaunch emitted init + `beacons/home?conversation_id` + matching detail before user interaction.
- **Alternatives considered**: Continue extracting any UUID from `UIContextMenuConfiguration.identifier`; use visible title as primary target; restore “latest conversation request wins”; silently create Share links to discover current ID.
- **Rejected / do-not-repeat**: Do not treat arbitrary structural UUIDs as conversation IDs. Do not use title-only targeting. Do not silently call `/share/create` for identity discovery because it has a user-visible/privacy-relevant side effect. Do not generalize the proven `conversation/init` field back into generic network recency authority.
- **Affected modules**: `Core/CECore.*`, `Network/CENetworkObserver.*`, `UI/CEEnhancerUI.mm`, conversation-recognition feature consumers.
- **Validation level**: Real-device alpha46 trace + current source inspection. Share exactness is runtime-proven for tested flows; `conversation/init` is strongly validated in this trace but still requires successor-candidate action-target acceptance testing.
- **Supersedes**: Any implicit assumption that UUID syntax alone is sufficient conversation identity evidence.

## Rule

Do not write speculation here as fact. A historical plan is not proof of implementation.