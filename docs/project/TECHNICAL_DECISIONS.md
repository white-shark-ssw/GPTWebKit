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
- **Evidence**: Alpha47 request-only false success; alpha48 and alpha56 exposed UI-proof false negatives; later candidates retain the two-layer completion contract.
- **Rejected**: request-only success, artificial blanking, unrelated alternate-ID/navigation fallbacks.

## TD-011 — Sidebar conversation management is row-scoped, not active-context-scoped

- **Status**: Confirmed design contract / runtime acceptance pending
- **Date**: 2026-08-26
- **Decision**: Conversation-list Rename/Export target the selected row independently from active context. Row title may enumerate `CECatalog` candidates; duplicate titles require explicit choice. Sync/Reload remain absent from sidebar menus.

## TD-012 — Sync Latest treats HTTP 429 as terminal and does not equate fetch with UI synchronization

- **Status**: Confirmed design/source contract; runtime 429 acceptance pending
- **Date**: 2026-08-27
- **Decision**: `同步最新消息` uses the frozen exact ID and one guarded enhancer GET. HTTP 429 terminates the request; no burst-style automatic 429 retry. GET success is server-state evidence only. If server generation is active, do not force page refresh. If finished and current ID still matches, a host refresh may be requested, but visible success still follows TD-010.
- **Evidence**: User repeatedly observed plugin `1/3` after 429; source proved one tap could create up to four requests. Alpha51 removed 429 retries and added exact-ID Sync guards. Captured traces after alpha51 did not contain 429, so terminal-429 behavior is not yet device exercised by trace evidence.
- **Rejected**: treating `1/3` as OpenAI quota, guessed cooldown/quota thresholds, broad Catalog throttling without attribution evidence, GET-success-as-page-success.

## TD-013 — Proven request delivery suppresses repeated same-route refresh attempts

- **Status**: Confirmed from runtime evidence
- **Date**: 2026-08-27
- **Scope**: exact-current Sync → host refresh / manual Reload delivery
- **Decision**: `openURL(...)=YES` alone is not enough, but once an exact same-ID conversation request is actually observed after a refresh route, route delivery is proven. If the visible UI does not rebuild, continue the existing UI-proof observation window and report failure truthfully; **do not automatically send additional exact-route variants solely because UI did not change**. Alternate exact-current route delivery is allowed only when the previous route produced no same-ID request evidence at all. Operation wording must say `正在请求客户端刷新当前会话…`, not imply that a visible reload has begun.
- **Evidence**: Alpha51 trace showed repeated same-ID route requests with no visible benefit. Alpha53–56 retained one-delivery suppression and did not emit second/third route attempts after exact delivery proof.
- **Rejected / do-not-repeat**: Do not use repeated same-ID route requests as a substitute for discovering a genuine host refresh mechanism. Do not claim request/route acceptance as UI reload.

## TD-014 — Genuine host conversation navigation changes navigation state before exact init/prepare/detail; network traffic is evidence, not a replay recipe

- **Status**: Confirmed runtime correlation
- **Date**: 2026-08-27
- **Scope**: ChatGPT iOS visible conversation navigation/rebuild versus same-current custom-route refresh
- **Decision**: Treat exact `conversation/init → conversation/prepare → conversation detail` traffic as evidence that the official client has entered a conversation-navigation state. Do **not** infer that manually originating those requests would cause SwiftUI/UI navigation or rebuild. Public navigation structure/mutation/instance evidence describes host state; it is not authorization to recreate or mutate that state.
- **Evidence — alpha52/53/54**: Genuine navigation correlated with deeper public navigation state and init→prepare→detail; selected Objective-C NSURLSession task-creation hooks did not expose the upstream owner.
- **Evidence — alpha55**: Genuine navigation repeatedly used `pop 3→2` then `push 2→3`; same-current route used distinct `setViewControllers: 0→1`, proving a different host path.
- **Evidence — alpha56**: Trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D` proved the same-current route replaced active attached key-window nav token `nav-1` count 3 with a different active attached token `nav-2` count 1, followed by exact same-ID init/prepare/detail. User visibly observed a page refresh. This resolves the prior instance-ownership question: the route changes the active host navigation surface.
- **Rejected / do-not-repeat**: Do not replay init/prepare requests, force a three-controller stack, hard-code observed Swift controller classes, call UIKit pop/push/setViewControllers as a refresh fallback, reintroduce History/sidebar navigation, alternate IDs, guessed `/resume`, extra route variants, timers or watchdogs.

## TD-015 — Active attached navigation-controller replacement is valid UI rebuild evidence, not identity or mutation authority

- **Status**: Confirmed from alpha56 runtime evidence; alpha57 runtime acceptance pending
- **Date**: 2026-08-27
- **Scope**: `CEConversationUIReloadEvidence` completion proof
- **Decision**: When a Reload/Sync attempt begins with one active attached `UINavigationController` object and verification later resolves a different active attached `UINavigationController` object, that object replacement may count as **ephemeral UI rebuild evidence**. Visible success still requires the existing exact same-ID request proof; nav replacement alone is insufficient.
- **Evidence**: Alpha56 started on active attached `nav-1` count 3, route handling created a distinct `setViewControllers: 0→1`, exact same-ID init/prepare/detail followed, and verification resolved active attached `nav-2` count 1. The user explicitly saw one page refresh while the old scroll/anchor detector remained `baselineUI=unproven` and false-negatived.
- **Implementation boundary**: Alpha57 stores only ephemeral in-memory object identity in the reload snapshot. It does not persist pointers, does not write `CEConversationContext`, does not become a second state owner, and does not invoke navigation mutation APIs. Existing scroll-view replacement / anchor-turnover proof remains valid independently.
- **Rejected**: Treating nav presence as message-content proof; treating nav replacement as conversation identity; reporting success without same-ID request evidence; using the observed host replacement as authorization to call `setViewControllers`, push, or pop.
- **Validation**: Alpha57 **Code written → CI passed → Artifact produced; Runtime/manual pending**.

## TD-016 — Do not infer a callable ObjC owner or reconstruct addresses from sanitized textual Swift backtraces

- **Status**: Confirmed from alpha60 runtime evidence
- **Date**: 2026-08-30
- **Scope**: conversation recognition / official host transition diagnostics
- **Decision**: Semantic Swift runtime class names are discovery evidence only; they do not imply an Objective-C selector surface. Do not guess/invoke private selectors from classes such as `Conversations.*` or `ConversationFinalStream.*` when runtime method enumeration exposes no ObjC IMPs. Likewise, a persisted textual frame such as `ChatGPT + N` must not be converted back into an address using `_dyld_get_image_header(0) + N`.
- **Evidence**: Alpha60 trace `FE491226-23C8-4F76-8D4E-230A1840D930` enumerated 4991 app-bundle classes and relevant conversation Swift types but reported `mainIMPClasses=0`, `mainIMPMethods=0`, and `no-main-objc-method` for all historical references. Reconstructing textually recorded `ChatGPT + 48186293` from main base resolved into unrelated `LiveKitWebRTC`; other references were unresolved.
- **Next diagnostic boundary**: Actual return addresses may be used transiently in memory at the event site only to call `dladdr`; persistence is limited to sanitized image name, symbol name, frame order and symbol-relative delta. Raw addresses remain memory-only. If symbols are stripped, continue with resolved image/module identity and Swift runtime metadata rather than ObjC selector guessing or textual offset arithmetic.

## Rule

Do not write speculation here as fact. A historical plan is not proof of implementation.