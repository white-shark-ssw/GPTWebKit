# Project-Specific Rules

This file contains evidence-backed rules specific to this repository/product.

## Product contracts

- Current enhancer target is official ChatGPT iOS bundle `com.openai.chat`, iOS 17.0+, using plain dylib injection such as TrollFools / 巨魔注入器.
- `ChatGPTEnhancer/Sources/Bootstrap/CEBootstrap.mm` is the single enhancer startup owner. Do not add independent startup ownership.
- Feature code must use established state owners instead of independently guessing conversation IDs or duplicating request/UI ownership.
- Conversation Markdown export uses complete conversation data and must not load/render a conversation UI solely for export.

## Compatibility / deployment constraints

- Do not hard-code private ChatGPT Swift class names while a public UIKit/Foundation runtime alternative exists.
- Sensitive Authorization/cookie/account/request-template material copied from the host app remains memory-only and must not be persisted.
- User-started diagnostic persistence may store only minimum sanitized identity-correlation evidence: conversation ID/title and structural menu/request/UI metadata are allowed; Authorization, Cookie, account IDs, raw request templates, full headers, raw request/response bodies and message contents are prohibited.
- Enhancer compile target is arm64 iOS 17.0 and current build links Foundation, UIKit, QuartzCore and CoreGraphics.
- Compatibility changes for undocumented ChatGPT runtime/backend behavior require current source/runtime evidence, not guessed API structure.

## Critical invariants

- `CEConversationContext` is the sole long-lived authority for active conversation identity.
- `CENetworkObserver` owns passive official-network observation. Generic observed request URLs/conversation IDs are not foreground authority and must not directly mutate `CEConversationContext`. A narrowly scoped semantic signal may update the same owner only when its exact endpoint/field has direct runtime evidence.
- Conversation identity is **source/field-aware, not UUID-shape-aware**. UUID syntax alone is never proof of a conversation ID.
- Current-menu Sync / Reload / Rename / Export must never execute on a stale or guessed current conversation ID.
- **Current top-right menu actions are active-conversation actions.** They use the exact ID captured by the proven current-chat menu and fail closed if the sole current context no longer matches before execution.
- Current-menu Rename rechecks the exact captured ID immediately before issuing its PATCH after editing; title/source-view/menu UUID heuristics must not select the current-chat target.
- **Conversation-list/sidebar Rename / Export are selected-row actions, not active-context actions.** They never borrow or mutate `CEConversationContext`; row presentation/accessibility title may only enumerate `CECatalog` candidates. A unique candidate may execute; duplicate titles require explicit user selection; zero candidates fail closed. Sync / Reload must not be added to sidebar row menus.
- Menu-scoped exact current target and sidebar candidate sets are ephemeral action evidence, not second long-lived state owners.
- Title-only matching is not sufficient authority for current/destructive actions; sidebar title is permitted only to enumerate candidates and cannot silently resolve duplicates.
- Official Share-create body `conversation_id` is proven action-scoped ground truth, but `/share/create` is side-effectful and must never be invoked silently just to discover identity.
- **Server Sync GET success is not visible synchronization.** It proves server-state retrieval only.
- **Reload/request delivery is not Reload completion.** `openURL(...)=YES` or a same-ID conversation detail request proves delivery only; UI refresh/rebuild must also be proven before success is reported.
- **Once exact same-ID request delivery is proven, do not automatically repeat the same refresh route merely because the UI did not rebuild.** Continue observing the existing proof window and fail truthfully if the page remains unchanged. Alternate same-ID delivery is permitted only when prior route delivery produced no same-ID request evidence.
- **Reload UI refresh/rebuild is not interrupted-generation recovery.** A rebuilt page that remains `正在思考` is not proof that the old stream resumed or terminated correctly.
- HTTP 429 is terminal for the current enhancer request; do not amplify server throttling with short automatic 429 retries. Numeric `Retry-After` may be surfaced when present; do not invent quota thresholds or cooldowns.
- Enhancer-generated project conversation titles are presentation only and must never become identity evidence.
- `CEAPIClient` is the only component allowed to originate enhancer ChatGPT requests.
- `CECatalog` owns conversation catalog/title/update-time state.
- `CEEnhancerUI` owns host-app UI integration; feature modules must not establish competing UIKit hook ownership.
- Candidate identity must stay synchronized across `CEVersion`, `ChatGPTEnhancer/build.sh`, and `build-enhancer.yml` artifact names.

## Confirmed contracts requiring evidence before superseding

No product module is currently marked Frozen, but these confirmed contracts must not be casually bypassed:

- Authentication/request templates are memory-only.
- Export does not load a conversation UI.
- Manual refresh/reload is exact-current-conversation only.
- Current-menu Rename is exact-current only with a final same-ID guard before PATCH.
- Sidebar Rename/Export target the selected row, never active current context; duplicate row titles remain explicit ambiguity.
- Generic/background official traffic does not determine foreground identity.
- Arbitrary UUID syntax is not conversation identity evidence.
- Sync GET success is not page synchronization.
- Request delivery is not page reload completion.
- Repeated same-route delivery after request delivery is already proven is prohibited without new runtime evidence.
- Page rebuild is not interrupted-generation recovery.

## Code style / naming constraints

- Follow existing Objective-C++/Swift naming and module boundaries. Do not rename established APIs/state owners merely for stylistic consistency.
- Keep changes minimal and evidence-driven. Avoid unrelated refactors or broad formatting churn.

## Prohibited routes / known dangerous regressions

- For current conversation refresh/reload, do not fall back to History-row automation, Sidebar automation, UIKit pop/push, or another conversation ID without a new evidence-backed decision.
- Do not restore alpha42 behavior where arbitrary observed conversation traffic or a generic `NSURLSessionTask.resume` probe writes identity into `CEConversationContext`.
- Do not execute Sync/Reload/Rename/current Export merely because context still contains an old ID when current proof failed.
- Do not use or mutate `CEConversationContext` to target a non-current/sidebar row.
- Do not silently choose first/newest among duplicate sidebar-title candidates.
- Do not add Sync/Reload to sidebar long-press menus.
- Do not restore arbitrary UUID/title/source candidate guessing as current-chat action authority.
- Do not persist Authorization, cookies, account IDs, raw host request templates, full headers, raw bodies or message contents.
- Do not introduce a second active-conversation authority, request client, catalog authority or feature-local UI hook framework without an explicit architectural decision.
- Do not treat visible title, Rename prefill, Share title or arbitrary menu/config UUID as proof of current conversation ID.
- Do not silently invoke `/backend-api/share/create` for identity.
- Do not add speculative `/resume`, generation retry loop, watchdog or forced terminal-status override because a page is stuck at `正在思考`; first capture the host's real request/error/status sequence.
- Do not treat the diagnostic A→B→A navigation sequence as authorization to implement History/sidebar navigation as production Reload. It is evidence collection only.
- Do not treat legacy `GPTWebKit` WebView/native behavior as current enhancer architecture by default.

## Rule maintenance

Update this file only from confirmed runtime/source evidence or explicit user requirements. Never turn a temporary hypothesis into a permanent rule.