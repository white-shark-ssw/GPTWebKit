# Project Profile

## Initialization

**Initialized** — 2026-08-25 from real repository evidence. Unknown facts remain `Unknown / Unverified`.

## Identity

- **Project name**: `GPTWebKit` repository; current active product track is `ChatGPTEnhancer`.
- **Repository**: `white-shark-ssw/GPTWebKit`.
- **Project purpose**: iOS tooling that augments ChatGPT usage. The active track injects a dylib into the official ChatGPT iOS app to add conversation export/management/reload/diagnostic UI and exact-current-conversation-aware behavior. Older branches contain standalone/native ChatGPT utility and WebView experiments.
- **Product type**: current track — injected iOS dynamic library / host-app enhancer. Legacy tracks — native iOS app / WebView utility.
- **Primary users/runtime**: official ChatGPT iOS bundle `com.openai.chat`, iOS 17.0+, plain dylib injection such as TrollFools / 巨魔注入器.

## Technology stack

- **Primary language(s)**: Objective-C++ (`.mm`) for `ChatGPTEnhancer`; Swift for legacy/native `GPTWebKit`; Bash for packaging; YAML for GitHub Actions.
- **Framework(s)**: UIKit, Foundation, QuartzCore, CoreGraphics for enhancer.
- **Package/dependency manager(s)**: no third-party dependency manifest found. `Unknown / Unverified` beyond Apple system frameworks.
- **Important configs**: `ChatGPTEnhancer/Support/ChatGPTEnhancer.plist`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml`, legacy Xcode project/workflow files.

## Repository structure / state owners

- **Current source root**: `ChatGPTEnhancer/Sources/`; legacy app root `GPTWebKit/`.
- **Startup owner**: `ChatGPTEnhancer/Sources/Bootstrap/CEBootstrap.mm`.
- **Tests**: no automated unit/UI test root verified.
- **Key owners**:
  - `Core/CECore` / `CEConversationContext` — shared helpers and sole long-lived active-conversation state authority. `CEForegroundWindows()` is a public-UIKit surface helper only, not conversation state.
  - `Core/CEContextResolver` — compatibility getter for current exact context; old periodic UIKit/title resolver is retired.
  - `Network/CENetworkObserver` — official-network observation/template/events/catalog input. Generic observed request IDs are passive; only the specifically validated explicit `POST /backend-api/conversation/init` request-body conversation ID may promote foreground identity into the existing context owner.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog and presentation title owner.
  - `UI/CEEnhancerUI` — host UIKit integration, immutable exact current-header actions, row-scoped sidebar Rename/Export, project-header presentation.
  - `UI/CEConversationUIReloadEvidence` — public-UIKit ephemeral current-message-view snapshot/rebuild evidence for manual Reload completion; not an identity owner.
  - `Export/CEMarkdownExporter` — Markdown generation.
  - `Features/*` — exact-ID Pull/Rename/Reload/recovery behavior and candidate-based sidebar Rename/Export business paths.
  - `Diagnostics/CEConversationIdentityTrace` — optional persistent sanitized menu/network/Share/UI-structure evidence recorder; not an identity authority.
  - other `Diagnostics/*` — runtime probes/recovery diagnostics.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated unit/UI test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger for one CI candidate and remove it afterward.
- **Newest enhancer artifact**: `0.1.0-alpha50-sidebar-menu-actions`; Actions `32984372907`, job `98228416235`; package id `9612825155`, dylib id `9612825334`.
- **Current validation**: alpha50 = **Code written → CI passed → Artifact produced; Runtime/manual pending**. Alpha49 has partial device evidence: current top-right custom menu works, while sidebar long-press custom actions were missing and motivated alpha50. Project-header/Reload UI-proof acceptance remains pending in the lineage.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains a separate Active candidate. Current recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` artifact/package names must match.
- **Current recognition candidate**: `0.1.0-alpha50-sidebar-menu-actions`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app.
- **Compiler target**: `arm64-apple-ios17.0`.
- **Auth/request context**: host authentication/account/request templates remain memory-only.
- **Current identity rule**: exact foreground identity is semantic/source-aware. Generic/background conversation request recency, arbitrary UIKit/menu UUIDs and title-only matching are not current-chat authority. The validated explicit `conversation/init` body ID updates the sole `CEConversationContext`; the top-right current-chat menu freezes that exact ID for Pull/Reload/Rename/Export.
- **Current Rename rule**: current-menu Rename uses the frozen exact ID and rechecks the same context immediately before PATCH execution; title/source-view candidates cannot choose the current-chat rename target.
- **Sidebar management rule**: conversation-list/non-current long-press Rename/Export are selected-row management actions, not current-conversation actions. They must not borrow or mutate `CEConversationContext`. A catalog-known row title may produce a candidate set; duplicate titles require explicit user selection and no arbitrary structural UUID may become identity.
- **Reload completion rule**: observing a same-ID official request proves delivery, not completion. Reload success also requires current conversation UI rebuild/refresh evidence; runtime acceptance remains pending.
- **Presentation-title rule**: the exact current-chat official menu/catalog title may present the real conversation title in a project header for an already-proven ID. The plugin-generated label is synthetic and never identity evidence; runtime acceptance remains pending.
- **Generation recovery rule**: page reload/rebuild does not prove a previously interrupted generation recovered. No speculative resume/retry/watchdog is authorized without a trace capturing the host lifecycle from before prompt send/disconnect.
- **Diagnostic persistence exception scope**: user-started sanitized identity correlation data may persist conversation IDs/titles plus structural menu/request/UI metadata. Authorization, cookies, account IDs, raw request templates, full headers, raw bodies and message contents remain prohibited.

## Documentation evidence

- Base branch remains `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked after alpha50 CI on 2026-08-26.
- Alpha46 runtime trace established exact semantic current-chat identity evidence and invalidated arbitrary menu UUID identity.
- Alpha49 build/test source `3f3a04715e93755c1c04b4ca826aad2488c2a9a1`; user later confirmed top-right custom actions work but sidebar long-press lacked enhancer actions.
- Alpha50 build/test source `44b7baf84458c19c963ce0a7ee0d869da28dfe08`; Actions `32984372907`; CI bookkeeping `7988e2c06c38c419885f815e4960a892c08fe28f`; post-CI cleanup/current head `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac` differs from tested source only by run-id bookkeeping and removal of the temporary branch trigger.
- Alpha50 package digest `sha256:d19595daa76d7ecc1eb5432a68c6cf70ceb77912c094ac5aad0ecead45c5a983`; dylib artifact digest `sha256:5580d466418c2e6ba7c6ad7eab46861e0efb8e65ca59b489a58e6356825ca8b7`.
- Legacy tracks remain separate and are not current enhancer baseline evidence.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, major state ownership or newest artifact/baseline changes.