# Technical Decisions

This file records durable, evidence-backed technical decisions and rejected routes.

## TD-001 — Enhancer state ownership is centralized by subsystem

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Scope**: `ChatGPTEnhancer`
- **Decision**: Keep one constructor (`CEBootstrap`); use `CEConversationContext` for active conversation identity; `CENetworkObserver` for official-network observation; `CEAPIClient` for enhancer-originated requests; `CECatalog` for catalog state; `CEEnhancerUI` for host UI integration.
- **Rejected**: duplicate feature-local state owners, request stacks or UI-hook frameworks.

## TD-002 — Sensitive host authentication context is memory-only

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Decision**: Authorization/account headers and raw official request templates may be reused in memory but must not be persisted.

## TD-003 — Markdown export uses complete conversation data, not UI rendering

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Decision**: Export complete conversation JSON by exact ID and follow `current_node -> parent -> root`; do not load a conversation UI solely for export.

## TD-004 — Manual reload is exact-current-conversation only

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Decision**: Refresh/Reload may target only the exact active conversation ID and must stop if app state/context changes. History/sidebar automation, UIKit pop/push and alternate conversation IDs are not reload fallbacks without a new evidence-backed decision.
- **Notes**: Request delivery proves delivery only; completion is constrained by TD-010 and TD-013.

## TD-005 — Enhancer-generated conversation titles are presentation, never identity evidence

- **Status**: Confirmed
- **Date**: 2026-08-25
- **Decision**: Plugin-generated or official visible titles may update presentation metadata only after exact identity is independently proven. They cannot select/change/reinforce active conversation identity.

## TD-006 — Standalone ChatGPT client uses native iOS presentation, not WebView chat rendering

- **Status**: Confirmed planning direction
- **Date**: 2026-08-25
- **Scope**: `DEV-native-chatgpt-client`
- **Decision**: A future standalone client uses native iOS conversation presentation; WebView is not the primary long-conversation renderer. This does not alter current enhancer architecture.

## TD-007 — Observed conversation network requests are not foreground identity authority

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Decision**: Generic observed official/background request URLs must not set `CEConversationContext`. Current Sync/Reload/Rename/Export require exact current proof and stale fallback is prohibited.
- **Evidence**: Alpha42 runtime cross-target failure from generic network-driven writers.

## TD-008 — Floating tool availability is separate from conversation identity

- **Status**: Confirmed / historical
- **Date**: 2026-08-26
- **Decision**: Tool-surface visibility is not identity evidence. Conversation-tool floating UI was later retired in favor of exact current-chat menu actions; percentage UI remains separate.

## TD-009 — Conversation identity evidence is semantic/source-aware, not UUID-shape-aware

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Decision**: UUID syntax is not identity evidence. Alpha46 proved Share-create body `conversation_id` as an action-scoped oracle and strongly validated explicit `POST /backend-api/conversation/init` body `conversation_id` as foreground existing-conversation navigation evidence. Alpha47+ promotes only that semantic init field into the sole context owner and freezes it into current-menu actions.
- **Rejected**: arbitrary menu/config UUIDs, title-only current targeting, generic latest-request authority, silent Share creation.

## TD-010 — Reload request delivery is not Reload completion

- **Status**: Confirmed
- **Date**: 2026-08-26
- **Decision**: A same-ID official request proves custom-route/request delivery only. Visible Reload success requires both exact same-ID request evidence and current message-page refresh/rebuild evidence. A blank screen itself is not required.
- **Evidence**: Alpha47 request-only false success; alpha48 UI-proof false-negative on one visible refresh; later candidates retain the two-layer completion contract.
- **Rejected**: request-only success, artificial blanking, unrelated alternate-ID/navigation fallbacks.

## TD-011 — Sidebar conversation management is row-scoped, not active-context-scoped

- **Status**: Confirmed design contract / runtime acceptance pending
- **Date**: 2026-08-26
- **Decision**: Conversation-list Rename/Export target the selected row independently from active context. Row title may enumerate `CECatalog` candidates; duplicate titles require explicit choice. Sync/Reload remain absent from sidebar menus.

## TD-012 — Sync Latest treats HTTP 429 as terminal and does not equate fetch with UI synchronization

- **Status**: Confirmed design/source contract; runtime 429 acceptance pending
- **Date**: 2026-08-27
- **Decision**: `同步最新消息` uses the frozen exact ID and one guarded enhancer GET. HTTP 429 terminates the request; no burst-style automatic 429 retry. GET success is server-state evidence only. If server generation is active, do not force page refresh. If finished and current ID still matches, a host refresh may be requested, but visible success still follows TD-010.
- **Evidence**: User repeatedly observed plugin `1/3` after 429; source proved one tap could create up to four requests. Alpha51 removed 429 retries and added exact-ID Sync guards. Alpha51/52/53 captured traces did not contain 429, so terminal-429 behavior is not yet device exercised by trace evidence.
- **Rejected**: treating `1/3` as OpenAI quota, guessed cooldown/quota thresholds, broad Catalog throttling without attribution evidence, GET-success-as-page-success.

## TD-013 — Proven request delivery suppresses repeated same-route refresh attempts

- **Status**: Confirmed from runtime evidence
- **Date**: 2026-08-27
- **Scope**: exact-current Sync → host refresh / manual Reload delivery
- **Decision**: `openURL(...)=YES` alone is not enough, but once an exact same-ID conversation request is actually observed after a refresh route, route delivery is proven. If the visible UI does not rebuild, continue the existing UI-proof observation window and report failure truthfully; **do not automatically send additional exact-route variants solely because UI did not change**. Alternate exact-current route delivery is allowed only when the previous route produced no same-ID request evidence at all. Operation wording must say `正在请求客户端刷新当前会话…`, not imply that a visible reload has begun.
- **Evidence**: Alpha51 trace showed three route attempts each produced only another same-ID detail GET without visible rebuild. Alpha53 trace `E076722C-E0F0-4044-8B99-41F727B1B62B` exercised the alpha52 suppression logic: after route attempt 0 produced one same-ID detail GET and no UI rebuild, it emitted `stop-repeat-route` and ended without attempts 1/2.
- **Rejected / do-not-repeat**: Do not use repeated same-ID route requests as a substitute for discovering a genuine host refresh mechanism. Do not claim request/route acceptance as UI reload.

## TD-014 — Genuine host conversation navigation emits init → prepare → detail; this traffic is evidence, not a replay recipe

- **Status**: Confirmed runtime correlation; production refresh entry point still unverified
- **Date**: 2026-08-27
- **Scope**: ChatGPT iOS visible conversation navigation/rebuild versus same-current custom-route refresh
- **Decision**: Treat exact `conversation/init → conversation/prepare → conversation detail` traffic as evidence that the official client has already entered a genuine conversation-navigation state. Do **not** infer that manually originating those same network requests from the enhancer would cause the host SwiftUI/UI state to transition or rebuild. A production refresh mechanism must target an evidenced host-side navigation/refresh owner, not replay network consequences.
- **Evidence**: Alpha52 trace `585B0B11-C85D-4A19-BA16-4F55D56A320A` captured normal A→B→A. Alpha53 trace `E076722C-E0F0-4044-8B99-41F727B1B62B` reproduced the distinction with added structure: both exact genuine navigations produced init followed by prepare/detail within ~125 ms and showed `SwiftUI.UIKitNavigationController navCount=3`; the same-A custom-route Sync/Reload produced one detail GET only, no exact init/prepare, no UI rebuild, and reported `navCount=1` at that detail request.
- **Diagnostic limitation now confirmed**: All 11 alpha53 `REFRESH-PATH` call-stack signatures were identical across genuine init/prepare/detail and failed same-current detail. The current stack capture point in `CEConversationIdentityTraceLogRequest` is therefore too downstream/common to identify the upstream host navigation caller and must not be treated as production-entry evidence.
- **Implication**: The custom URL path reaches a structurally different/incomplete public navigation-container state, but the evidence does not justify force-restoring a navigation stack or calling UIKit pop/push. A narrower diagnostic may move capture closer to task creation and record bounded stack composition / ID-less init/prepare staging before a production change.
- **Rejected / do-not-repeat**: Do not replay init/prepare requests merely because genuine navigation emits them. Do not force navigation-stack restoration from `navCount` alone. Do not reintroduce History/sidebar navigation, alternate IDs, UIKit pop/push, guessed `/resume`, timers or watchdogs as substitutes for identifying the real host entry path.
- **Validation level**: alpha52 and alpha53 real-device traces. Production refresh remains unverified.

## Rule

Do not write speculation here as fact. A historical plan is not proof of implementation.