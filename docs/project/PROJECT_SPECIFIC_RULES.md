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
- User-started diagnostic persistence may store only the minimum sanitized identity correlation evidence required by the current investigation. Conversation ID/title and structural menu/request metadata are allowed for that explicit trace session; Authorization, Cookie, account IDs, raw request templates, full headers, raw request/response bodies and message contents are prohibited from persistence.
- Enhancer compile target is arm64 iOS 17.0; current build links Foundation, UIKit, QuartzCore and CoreGraphics.
- The project depends on undocumented ChatGPT runtime/backend behavior; any compatibility change must be supported by current source/runtime evidence, not guessed API structure.

## Critical invariants

- `CEConversationContext` is the sole long-lived authority for active conversation identity.
- `CENetworkObserver` owns passive official-network observation and request-template/event capture. **Observed request URLs/conversation IDs are not foreground conversation authority and must not directly mutate `CEConversationContext`.**
- Pull Latest, manual Reload, and current-conversation Export must never execute on a stale/guessed conversation ID. Existing candidates may fail closed while exact identification is under investigation; the final design must also eliminate routine false-negative refusal rather than masking it with stale fallback.
- Any future menu-scoped exact action target must be ephemeral evidence captured for that action, not a second long-lived current-conversation state owner.
- Title-only matching is not sufficient authority for destructive/current-conversation actions; duplicate-title cases must be supported without guessing.
- **Floating-button visibility is UI availability only, never conversation-identity evidence.** Until the menu-based design is proven and deliberately replaces it, the floating entry point must not disappear merely because current identity is unknown.
- `CEAPIClient` is the only component allowed to originate enhancer ChatGPT requests.
- `CECatalog` owns conversation ID/title/update-time catalog state.
- `CEEnhancerUI` owns host-app UI integration; feature modules should not establish competing UIKit hook ownership.
- Enhancer candidate identity must be synchronized across `CEVersion`, `ChatGPTEnhancer/build.sh`, and `build-enhancer.yml` artifact names.

## Frozen business or architecture rules

No module is marked Frozen by initialization. The following confirmed contracts still require explicit evidence before being superseded:

- Authentication/request templates are memory-only.
- Export does not load a conversation UI.
- Manual reload is exact-current-conversation only.
- Generic/background official network traffic does not determine foreground conversation identity.
- Floating-button visibility does not prove or require a current conversation identity while that UI remains part of the product.

## Code style / naming constraints

- Follow existing Objective-C++/Swift naming and module boundaries. Do not rename existing APIs/state owners merely for stylistic consistency.
- Keep changes minimal and evidence-driven. Avoid unrelated refactors or broad formatting churn.

## Prohibited routes / known dangerous regressions

- For manual conversation reload, do **not** fall back to History-row automation, Sidebar automation, UIKit pop/push, or another conversation ID. Alpha39 explicitly removed that route and verifies the official request for the same conversation.
- Do not restore the alpha42 behavior where `CENetworkObserver.observeRequest:` or a generic `NSURLSessionTask.resume` probe writes an observed conversation ID into `CEConversationContext`. Alpha42 real-device testing proved this lineage can cross conversations.
- Do not execute Pull/Reload/current Export merely because `CEConversationContext` still contains an old ID when current exact proof failed.
- Do not hide/remove the floating-tool entry merely because `CEConversationContext.conversationID` is empty while that entry remains the active UX; alpha44 real-device testing proved this makes guarded functionality inaccessible.
- Do not persist Authorization, cookies, account IDs, raw host request templates, full headers, raw request/response bodies or message contents, including in diagnostic logging.
- Do not introduce a second active-conversation authority, second enhancer request client, second catalog authority or feature-local UI hook framework without an explicit architectural decision.
- Do not treat a correct visible title, Rename prefill, or Share title as proof of exact conversation ID. Runtime evidence must identify the exact ID source, including duplicate-title cases.
- Do not treat legacy `GPTWebKit` WebView/native app behavior as the enhancer architecture by default. A task must explicitly identify the product track it is changing.

## Rule maintenance

Rules work may update this file proactively when a durable project-specific constraint is confirmed. Never turn a temporary hypothesis into a permanent rule.