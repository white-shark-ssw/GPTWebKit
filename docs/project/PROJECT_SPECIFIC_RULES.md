# Project-Specific Rules

This file contains rules specific to this repository/product. These rules are evidence-backed from current source/architecture/CI or explicit user requirements.

## Product contracts

- Current enhancer target is the official ChatGPT iOS app bundle `com.openai.chat`, iOS 17.0+, using plain dylib injection such as TrollFools / 巨魔注入器.
- `ChatGPTEnhancer/Sources/Bootstrap/CEBootstrap.mm` is the single enhancer constructor/startup entry. Do not add independent constructors for new features.
- Feature code must use the established state owners instead of independently guessing conversation IDs or duplicating request/UI ownership.
- Conversation Markdown export must use complete conversation data and must not load/render a conversation UI solely to export it.

## Compatibility / deployment constraints

- Do not hard-code private ChatGPT Swift class names while a public UIKit/Foundation runtime alternative exists. Current compatibility strategy intentionally hooks public UIKit/Foundation surfaces and recognizes request/menu behavior at runtime.
- Sensitive Authorization/cookie/account/request-template material copied from the host app must remain memory-only and must not be persisted.
- Enhancer compile target is arm64 iOS 17.0; current build links Foundation, UIKit, QuartzCore and CoreGraphics.
- The project depends on undocumented ChatGPT runtime/backend behavior; any compatibility change must be supported by current source/runtime evidence, not guessed API structure.

## Critical invariants

- `CEConversationContext` is the authority for active conversation identity.
- `CENetworkObserver` owns passive official-network observation and request-template/event capture.
- `CEAPIClient` is the only component allowed to originate enhancer ChatGPT requests.
- `CECatalog` owns conversation ID/title/update-time catalog state.
- `CEEnhancerUI` owns host-app UI integration; feature modules should not establish competing UIKit hook ownership.
- Enhancer candidate identity must be synchronized across `CEVersion`, `ChatGPTEnhancer/build.sh`, and `build-enhancer.yml` artifact names.

## Frozen business or architecture rules

No module is marked Frozen by initialization. The following confirmed contracts still require explicit evidence before being superseded:

- Authentication/request templates are memory-only.
- Export does not load a conversation UI.
- Manual reload is exact-current-conversation only.

## Code style / naming constraints

- Follow existing Objective-C++/Swift naming and module boundaries. Do not rename existing APIs/state owners merely for stylistic consistency.
- Keep changes minimal and evidence-driven. Avoid unrelated refactors or broad formatting churn.

## Prohibited routes / known dangerous regressions

- For manual conversation reload, do **not** fall back to History-row automation, Sidebar automation, UIKit pop/push, or another conversation ID. Alpha39 explicitly removed that route and verifies the official request for the same conversation.
- Do not persist Authorization, cookies, account IDs or raw host request templates.
- Do not introduce a second active-conversation authority, second enhancer request client, second catalog authority or feature-local UI hook framework without an explicit architectural decision.
- Do not treat legacy `GPTWebKit` WebView/native app behavior as the enhancer architecture by default. A task must explicitly identify the product track it is changing.

## Rule maintenance

Rules work may update this file proactively when a durable project-specific constraint is confirmed. Never turn a temporary hypothesis into a permanent rule.
