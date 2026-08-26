# Project-Specific Rules

This file contains rules specific to this repository/product. These rules are evidence-backed from current source/architecture/CI or explicit user requirements.

## Product contracts

- Current enhancer target is the official ChatGPT iOS app bundle `com.openai.chat`, iOS 17.0+, using plain dylib injection such as TrollFools / 巨魔注入器.
- `ChatGPTEnhancer/Sources/Bootstrap/CEBootstrap.mm` is the single enhancer startup owner. Do not add independent startup ownership for new features.
- Feature code must use the established state owners instead of independently guessing conversation IDs or duplicating request/UI ownership.
- Conversation Markdown export must use complete conversation data and must not load/render a conversation UI solely to export it.

## Compatibility / deployment constraints

- Do not hard-code private ChatGPT Swift class names while a public UIKit/Foundation runtime alternative exists. Current compatibility strategy intentionally hooks public UIKit/Foundation surfaces and recognizes request/menu behavior at runtime.
- Sensitive Authorization/cookie/account/request-template material copied from the host app must remain memory-only and must not be persisted.
- User-started diagnostic persistence may store only the minimum sanitized identity correlation evidence required by the current investigation. Conversation ID/title and structural menu/request/UI metadata are allowed for that explicit trace session; Authorization, Cookie, account IDs, raw request templates, full headers, raw request/response bodies and message contents are prohibited from persistence.
- Enhancer compile target is arm64 iOS 17.0; current build links Foundation, UIKit, QuartzCore and CoreGraphics.
- The project depends on undocumented ChatGPT runtime/backend behavior; any compatibility change must be supported by current source/runtime evidence, not guessed API structure.

## Critical invariants

- `CEConversationContext` is the sole long-lived authority for active conversation identity.
- `CENetworkObserver` owns passive official-network observation and request-template/event capture. **Generic observed request URLs/conversation IDs are not foreground conversation authority and must not directly mutate `CEConversationContext`.** A narrowly scoped semantic signal may update the same owner only when its exact endpoint/field has direct runtime evidence.
- Conversation identity parsing is **source/field-aware, not UUID-shape-aware**. A UUID found in an arbitrary UIKit/menu/configuration string is not a conversation ID. Accept exact IDs only from semantically proven conversation fields/paths such as explicit JSON `conversation_id` or backend conversation routes whose identity semantics are verified.
- Pull Latest, manual Reload, current-conversation Rename, and current-conversation Export must never execute on a stale/guessed conversation ID.
- **Current top-right menu actions are active-conversation actions.** Pull / Reload / Rename / Export use the exact ID captured by the proven current-chat menu and fail closed if the sole current context no longer matches before execution.
- Current-menu Rename must recheck the exact captured conversation ID immediately before issuing its PATCH after the user finishes editing the title; title/source-view/menu UUID candidate heuristics must not select the current-chat rename target.
- **Conversation-list/sidebar long-press Rename / Export are row-scoped management actions, not active-conversation actions.** They must never borrow or mutate `CEConversationContext` to target the selected row. The selected row's presentation/accessibility title may only produce a `CECatalog` candidate set. A unique candidate may be used; duplicate titles require explicit user selection; no candidate must fail closed. Pull / Reload must not be added to sidebar row menus.
- Menu-scoped exact current target and sidebar row candidate set are ephemeral action evidence, not second long-lived conversation state owners.
- Title-only matching is not sufficient authority for destructive/current-conversation actions. For sidebar management, a title is permitted only to enumerate catalog candidates; it cannot silently choose among duplicate-title conversations.
- Official Share-create body `conversation_id` is proven ground-truth identity evidence for the Share action, but `/share/create` is side-effectful and must not be invoked silently just to discover identity.
- **Reload request delivery is not Reload completion.** Do not report success from request observation alone; current conversation UI refresh/rebuild must also be proven.
- **Reload UI refresh/rebuild is not interrupted-generation recovery.** If a prior live response timed out/disconnected, a page that rebuilt but remains stuck at `正在思考` is not proof that the generation stream resumed or reached a terminal state. Recovery behavior must be based on observed official stream/status semantics, not guessed resume calls or timers.
- Enhancer-generated project conversation titles are presentation only and must never become identity evidence.
- `CEAPIClient` is the only component allowed to originate enhancer ChatGPT requests.
- `CECatalog` owns conversation ID/title/update-time catalog state.
- `CEEnhancerUI` owns host-app UI integration; feature modules should not establish competing UIKit hook ownership.
- Enhancer candidate identity must be synchronized across `CEVersion`, `ChatGPTEnhancer/build.sh`, and `build-enhancer.yml` artifact names.

## Frozen business or architecture rules

No module is marked Frozen by initialization. The following confirmed contracts still require explicit evidence before being superseded:

- Authentication/request templates are memory-only.
- Export does not load a conversation UI.
- Manual reload is exact-current-conversation only.
- Current-menu Rename is exact-current-conversation only and requires a final same-ID guard before PATCH.
- Sidebar Rename/Export target the selected row candidate, never the active current context; duplicate row titles remain explicit ambiguity.
- Generic/background official network traffic does not determine foreground conversation identity.
- Arbitrary UUID syntax is not conversation identity evidence.
- Reload success cannot be inferred from request delivery alone.
- A page rebuild cannot be equated with recovery of an interrupted generation stream.

## Code style / naming constraints

- Follow existing Objective-C++/Swift naming and module boundaries. Do not rename existing APIs/state owners merely for stylistic consistency.
- Keep changes minimal and evidence-driven. Avoid unrelated refactors or broad formatting churn.

## Prohibited routes / known dangerous regressions

- For manual conversation reload, do **not** fall back to History-row automation, Sidebar automation, UIKit pop/push, or another conversation ID.
- Do not restore the alpha42 behavior where arbitrary observed conversation traffic or a generic `NSURLSessionTask.resume` probe writes an observed conversation ID into `CEConversationContext`.
- Do not execute Pull/Reload/Rename/current Export merely because `CEConversationContext` still contains an old ID when current exact proof failed.
- Do not use `CEConversationContext` as the target for a non-current/sidebar row's Rename/Export.
- Do not mutate active context merely because the user touched/long-pressed a sidebar row or because its title matched a catalog record.
- Do not silently choose first/newest among duplicate-title sidebar candidates; require explicit choice or fail closed.
- Do not add Pull/Reload to sidebar long-press menus.
- Do not restore alpha46 `CECandidatesForSourceView(...)` or equivalent arbitrary UUID/title/source candidate guessing as **current-chat** Rename/Pull/Reload/Export authority.
- Do not persist Authorization, cookies, account IDs, raw host request templates, full headers, raw request/response bodies or message contents, including in diagnostic logging.
- Do not introduce a second active-conversation authority, second enhancer request client, second catalog authority or feature-local UI hook framework without an explicit architectural decision.
- Do not treat a correct visible title, Rename prefill, Share title, or arbitrary UUID-looking menu/configuration identifier as proof of exact current conversation ID.
- Do not silently invoke `/backend-api/share/create` to identify the current conversation.
- Do not add a speculative `/resume` call, generation retry loop, watchdog, or forced terminal-status override merely because Reload left `正在思考`; first capture the host's real request/error/status sequence.
- Do not treat legacy `GPTWebKit` WebView/native app behavior as the enhancer architecture by default. A task must explicitly identify the product track it is changing.

## Rule maintenance

Rules work may update this file proactively when a durable project-specific constraint is confirmed. Never turn a temporary hypothesis into a permanent rule.