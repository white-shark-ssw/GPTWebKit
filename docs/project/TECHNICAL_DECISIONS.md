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
- **Decision**: Reload only the exact active conversation ID. Retry delivery through the official app's own custom route for the same conversation. Stop if app state/context changes. A request for that exact ID proves route/request delivery only; completion semantics are further constrained by TD-010.
- **Evidence**: Commit `8e520cba370870173a5ef08392636e1ca8036308`; alpha39 route behavior; alpha47–51 continuation.
- **Alternatives considered**: History-row/sidebar automation, UIKit pop/push navigation, using another conversation ID, orphaned-conversation fallback.
- **Rejected / do-not-repeat**: Do not use History rows, sidebar automation, UIKit pop/push, or another conversation ID as reload fallback unless a future explicit decision with new runtime evidence supersedes this rule.
- **Affected modules**: `Features/CEManualConversationReload.mm`, Network observer, current conversation context.
- **Validation level**: Exact-ID route behavior has CI/artifact lineage; candidate-specific runtime correctness is tracked separately.
- **Supersedes**: Older manual reload fallback route.

## TD-005 — Enhancer-generated conversation titles are presentation, never identity evidence

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: Enhancer current-conversation UI / identity resolution
- **Decision**: When `CEEnhancerUI` rewrites host-app presentation with a conversation title, mark that label as enhancer-synthetic and exclude its own text/accessibility values from all generic current-conversation evidence paths. Only independent semantic host/network evidence may change `CEConversationContext`. For an already-proven exact conversation ID, an official current-chat menu/catalog title may update presentation metadata and the project header, but it still cannot select, change or reinforce identity.
- **Evidence**: Alpha41 post-build review found a self-feedback cycle was possible: stale context A could write A's title into project chat B, after which visible-title resolution could read the plugin-generated A title and reinforce A. Alpha42 isolated marked synthetic presentation. Alpha46/47 later established exact ID independently of title; alpha48–50 use exact current menu title only after the target ID is already proven.
- **Alternatives considered**: Let the rewritten header participate in visible-title matching; create another header-local current-conversation state owner; use title to choose target ID.
- **Rejected / do-not-repeat**: Do not treat plugin-generated UI text, official visible title, Rename prefill or project header text as proof of active conversation identity and do not create a second conversation authority to compensate.
- **Affected modules**: `Core/CECore.*`, `UI/CEEnhancerUI.mm`, Storage presentation metadata.
- **Validation level**: Synthetic-title exclusion has code/CI lineage; project-header presentation runtime acceptance remains pending/paused.
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
- **Decision**: `CENetworkObserver` remains passive and must not set `CEConversationContext.conversationID` merely because an official request URL contains a conversation ID. Generic `NSURLSessionTask.resume` observation must not set foreground identity either. Sync, Reload, Rename and current-conversation Export must require exact current-conversation proof; stale context fallback is prohibited.
- **Evidence**: Alpha42 real-device testing showed Pull Latest and Reload crossing conversations. Source inspection found two independent unconditional network writers consuming arbitrary official/background conversation traffic. Alpha49 restores Rename on the same exact current-menu target contract rather than the older title/source candidate route; alpha51 retains exact targeting for renamed Sync.
- **Alternatives considered**: Treat most recent arbitrary request as current; debounce/timing heuristics; second visible-ID cache; title/source candidate targeting.
- **Rejected / do-not-repeat**: Do not infer foreground identity from generic request recency. Do not add retry/debounce/watchdog to mask the ownership error. Do not create a second active-conversation authority.
- **Affected modules**: Core, Network, UI, Features.
- **Validation level**: Runtime failure + source evidence; exact-current lineage has CI/artifact evidence and partial runtime evidence.
- **Supersedes**: Alpha42 generic observed-request authority.
- **Notes**: TD-009 narrows this rule with alpha46 evidence for one specific semantic endpoint/field; it does not restore generic network authority.

## TD-008 — Floating tool availability is separate from conversation identity

- **Status**: Confirmed / historical while floating tool existed
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer floating tools / current-conversation UX
- **Decision**: A floating tool button is application UI availability, not proof that a conversation ID is known. Its lifecycle must never be used as identity evidence. Alpha47 later deliberately retired the conversation-tool floating button in favor of exact current-chat menu actions; percentage UI remains a separate task.
- **Evidence**: Alpha44 removed unsafe network identity writes, after which the button disappeared because visibility was gated by non-empty context. Alpha45 separated UI availability from identity. User later approved retiring the conversation-tool floating surface.
- **Alternatives considered**: Restore network-derived identity for presentation; hide tools until identity is known.
- **Rejected / do-not-repeat**: Do not couple any future entry surface visibility to identity authority.
- **Affected modules**: `UI/CEEnhancerUI.mm`.
- **Validation level**: Runtime failure + source evidence + later product UX decision.
- **Supersedes**: Alpha44 ID-gated button lifecycle.

## TD-009 — Conversation identity evidence is semantic/source-aware, not UUID-shape-aware

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer current-conversation identity parsing and action targeting
- **Decision**: A UUID-looking string is not a conversation ID merely because it matches UUID syntax. Identity evidence must come from a semantically proven conversation location/field. Alpha46 proves `POST /backend-api/share/create` request-body `conversation_id` is an exact action-scoped ground-truth oracle, and provides strong evidence that `POST /backend-api/conversation/init` with an explicit body `conversation_id` is a foreground existing-conversation navigation signal. Alpha47 promotes only that explicit init field into the sole context owner and freezes it into current-menu actions. Alpha49 restores Rename using that same immutable exact menu ID and rechecks it again immediately before PATCH. Alpha51 keeps the same target for Sync.
- **Evidence**: Alpha46 real-device trace contained 13 unique UUID-looking menu/configuration identifiers with zero intersection with the 7 real conversation IDs observed in network traffic. The same trace captured 8 Share-create requests across 6 unique chats; each carried explicit body `conversation_id`, including two same-title `测试会话` chats with different IDs. For 7/7 Share events with a preceding explicit `conversation/init` body ID, the latest explicit init ID matched Share exactly. Cold relaunch emitted init + matching home/prepare/detail evidence before user interaction.
- **Alternatives considered**: Continue extracting any UUID from `UIContextMenuConfiguration.identifier`; use visible title as primary current target; restore “latest conversation request wins”; silently create Share links to discover current ID.
- **Rejected / do-not-repeat**: Do not treat arbitrary structural UUIDs as conversation IDs. Do not use title-only/source-view candidate targeting for current-chat actions. Do not silently call `/share/create` for identity discovery because it has a user-visible/privacy-relevant side effect. Do not generalize the proven `conversation/init` field back into generic network recency authority.
- **Affected modules**: Core, Network, UI, conversation-recognition feature consumers.
- **Validation level**: Real-device alpha46 trace + alpha47–50 partial runtime exact-menu evidence + alpha51 CI/artifact lineage; broader runtime acceptance remains pending.
- **Supersedes**: Any implicit assumption that UUID syntax alone is sufficient conversation identity evidence.

## TD-010 — Reload request delivery is not Reload completion

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer exact-current manual Reload completion semantics
- **Decision**: Observing the official request for the exact current conversation proves that the custom-route/reload request was delivered, but it does **not** prove that the current conversation page completed a reload. `✓ 当前会话已重载` may only be shown when both (1) exact same-ID official reload/detail request evidence and (2) current conversation UI/message-view refresh or rebuild evidence are present. If only request evidence is present, report the refresh as unconfirmed rather than success. Reuse the established same-ID reload attempt/poll lifecycle; do not introduce another timer/retry family/state authority.
- **Evidence**: Alpha47 real-device feedback showed request-only could report success without apparent page reload. Alpha48 added public-UIKit snapshots, but the subsequent real-device trace started `baselineUI=unproven` and never observed rebuild while the user visibly saw the page refresh, proving that alpha48's evidence target could false-negative. Alpha49 changed only public-UIKit surface selection to search visible foreground-scene windows; alpha50/51 preserve it.
- **Completion evidence**: conversation scroll view identity replacement, substantial visible message/text/accessibility anchor object turnover, or visible conversation content disappearing and then returning. A visible blank screen itself is not required. Runtime acceptance of the corrected surface discovery is pending.
- **Alternatives considered**: Keep request-only success; force an artificial blank screen; add a new watchdog/timer; use History/sidebar navigation; use another conversation ID.
- **Rejected / do-not-repeat**: Do not equate request observation with completed Reload. Do not manufacture a visual blank merely to satisfy the proof. Do not add unrelated retry/watchdog paths or alternate-ID/navigation fallbacks.
- **Affected modules**: `Features/CEManualConversationReload.mm`, `UI/CEConversationUIReloadEvidence.mm`, `UI/CEEnhancerUI.h`, `Core/CECore.*` public window helper.
- **Validation level**: Runtime evidence for alpha47/48 failure modes + later CI/artifact lineage; real-device completion classification pending.
- **Supersedes**: The request-only success condition used through alpha47 while preserving TD-004 exact-ID route constraints.

## TD-011 — Sidebar conversation management is row-scoped, not active-context-scoped

- **Status**: Confirmed design contract / runtime acceptance pending
- **Date**: 2026-08-26
- **Scope**: ChatGPTEnhancer conversation-list long-press Rename / Markdown Export
- **Decision**: The conversation-list/sidebar context menu is a management surface for the **selected row**, not a current-conversation surface. Sidebar `重命名会话` and `导出 Markdown` must never borrow or mutate `CEConversationContext` to decide their target. Public row/menu presentation/accessibility title may be used only to enumerate exact `CECatalog` records. One candidate may execute on that record ID; multiple same-title candidates require explicit user selection; zero candidates fail closed. Sync / Reload stay absent from sidebar menus. Arbitrary menu/configuration UUIDs are not valid row identity evidence.
- **Evidence**: Alpha49 real-device testing confirmed the top-right exact-current menu works but the conversation-list long-press had lost enhancer actions. Alpha50 restores only title→catalog-candidate enumeration and existing explicit candidate chooser; alpha51 leaves this path unchanged.
- **Alternatives considered**: Use current `CEConversationContext` for the long-pressed row; add current Sync/Reload to the sidebar; silently choose newest among duplicate titles; restore arbitrary UUID extraction; set active context from the long-press before acting.
- **Rejected / do-not-repeat**: Never use the active current conversation as a substitute for selected-row identity. Never mutate active context from sidebar touch/title evidence. Never silently choose one duplicate-title record. Never add current-only Sync/Reload to sidebar row menus without a separate evidence-backed design.
- **Affected modules**: `UI/CEEnhancerUI.mm`, existing `CEFeatures` candidate-based Rename/Export business paths, `CECatalog` as catalog owner.
- **Validation level**: User alpha49 runtime coverage failure + alpha50 Code written → CI passed → Artifact produced. Real-device selected-row/duplicate-title acceptance remains pending.
- **Supersedes**: Alpha49's blanket non-header-menu skip while preserving the exact-current header action contract.

## TD-012 — Sync Latest treats HTTP 429 as terminal and does not equate fetch with UI synchronization

- **Status**: Confirmed design/source contract; runtime acceptance pending
- **Date**: 2026-08-27
- **Scope**: ChatGPTEnhancer current-conversation Sync Latest and enhancer request rate-limit handling
- **Decision**: Rename the current action to `同步最新消息`. A manual Sync uses the frozen exact current conversation ID and at most one enhancer GET attempt for that Sync request. HTTP 429 terminates that request; `CEAPIClient` must not automatically burst-retry 429. Numeric `Retry-After` may be surfaced to the user, otherwise report that the user should retry later. A successful conversation GET is server-state evidence only, not proof that the visible page synchronized. If the server latest assistant result is still active, leave the live page/stream alone. If it is finished and the exact current ID still matches, reuse the established stale-stream safety and hand off to exact-current manual Reload; final visible success remains governed by TD-010 request+UI proof.
- **Evidence**: User repeatedly observed `请求频率受限，正在重试 1/3…`. Source inspection proved `1/3` was emitted only after `CEAPIClient` had already received HTTP 429, and the old generic policy could turn one tap into the original request plus up to three retries at short delays. Source also proved the old Pull JSON result was not applied to the host page. Alpha51 changes `CEAPIClient`, Sync operation state, menu wording and Reload handoff accordingly; Actions `33000977913` passed and artifacts were produced.
- **Alternatives considered**: Continue retrying 429 at `0.7/1.5/3.0s`; impose a guessed global cooldown; broadly throttle Catalog without attribution evidence; claim GET success as page synchronization; force Reload while server still reports active generation.
- **Rejected / do-not-repeat**: Do not interpret plugin `1/3` as an OpenAI quota counter. Do not automatically retry HTTP 429. Do not invent an OpenAI quota threshold or cooldown duration. Do not make broader Catalog traffic changes without request-count/status evidence. Do not force a live generation to Reload merely because Sync was tapped. Do not report page synchronization from GET success alone.
- **Affected modules**: `Network/CEAPIClient.mm`, `Features/CEForegroundStreamRecovery.mm`, `Features/CEFeatures.mm`, `UI/CEEnhancerUI.mm`.
- **Validation level**: Source evidence + alpha51 Code written → CI passed → Artifact produced. Runtime/manual pending.
- **Supersedes**: The prior generic HTTP 429 automatic-retry behavior and the old server-state-only `拉取最新消息` product semantics.

## Rule

Do not write speculation here as fact. A historical plan is not proof of implementation.