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
  - `Core/CECore` / `CEConversationContext` — shared helpers and sole long-lived active-conversation state authority.
  - `Core/CEContextResolver` — compatibility getter for current exact context; the old periodic UIKit/title resolver is retired.
  - `Network/CENetworkObserver` — official-network observation/template/events/catalog input. Generic observed request IDs are passive; only the specifically validated explicit `POST /backend-api/conversation/init` request-body conversation ID may promote foreground identity into the existing context owner.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog and presentation title owner.
  - `UI/CEEnhancerUI` — host UIKit integration, current-header menu augmentation, project-header presentation.
  - `UI/CEConversationUIReloadEvidence` — public-UIKit ephemeral current-message-view snapshot/rebuild evidence for manual Reload completion; not an identity owner.
  - `Export/CEMarkdownExporter` — Markdown generation.
  - `Features/*` — exact-ID Pull/Rename/Reload/recovery behavior.
  - `Diagnostics/CEConversationIdentityTrace` — optional persistent sanitized menu/network/Share identity evidence recorder; not an identity authority.
  - other `Diagnostics/*` — runtime probes/recovery diagnostics.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger for one CI candidate and remove it afterward.
- **Newest enhancer artifact**: `0.1.0-alpha48-reload-ui-title`; Actions `32973529739`, job `98192604072`; package id `9608529953`, dylib id `9608530563`. Runtime/manual acceptance pending.
- **Current validation**: alpha48 = Code written → CI passed → Artifact produced. Alpha47 reached partial real-device testing but exposed request-only false Reload success semantics. Alpha46 completed its instrumentation purpose and provided the identity evidence used by alpha47/48.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains a separate Active candidate stacked on older rejected recognition. Current recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` artifact/package names must match.
- **Current recognition candidate**: `0.1.0-alpha48-reload-ui-title`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app.
- **Compiler target**: `arm64-apple-ios17.0`.
- **Auth/request context**: host authentication/account/request templates remain memory-only.
- **Current identity rule**: exact foreground identity is semantic/source-aware. Generic/background conversation request recency, arbitrary UIKit/menu UUIDs and title-only matching are not authority. The validated explicit `conversation/init` body ID updates the sole `CEConversationContext`; top-right current-chat menu freezes that exact ID for Pull/Reload/Export.
- **Reload completion rule**: observing a same-ID official request proves delivery, not completion. A Reload success message now also requires current conversation UI rebuild/refresh evidence.
- **Presentation-title rule**: the exact current-chat official menu/catalog title may be used to present the real conversation title in a project header for an already-proven ID. The plugin-generated label is marked synthetic and never participates in identity evidence.
- **Diagnostic persistence exception scope**: user-started sanitized identity correlation data may persist conversation IDs/titles plus structural menu/request metadata. Authorization, cookies, account IDs, raw request templates, full headers, raw bodies and message contents remain prohibited.

## Documentation evidence

- Base branch remains `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` as rechecked before alpha48 CI on 2026-08-26.
- Alpha46 runtime trace established exact semantic identity evidence and invalidated arbitrary menu UUID identity.
- Alpha47 build/test source `d297f65971fb6239cad2be7eb7fa9f8f8aab9f6d`; Actions `32969623709`; package id `9607073111`; dylib id `9607074065`. Real-device Reload feedback showed request observation was insufficient as a completion criterion.
- Alpha48 build/test source `e2b133f0ba050b485e89129e4fe0ecb9bbee2343`; Actions `32973529739`; CI bookkeeping `7b2d9d9e709e431ec414b269bd72b4b33a092001`; post-CI cleanup/current head `17f76c8428dad41484641b9dcf23a78935dbc32f` differs from tested source only by run-id bookkeeping and removal of the temporary branch trigger.
- Alpha48 package digest `sha256:256746f6fe6f7ea01e5a3e6d90f3a8bd47fa9f606366565fab8687ef18baf6a2`; dylib artifact digest `sha256:a14dd7ae64931d45076459290fdd0674b3c9582c1b966e7fcb2d4b06814da840`.
- Legacy tracks remain separate and are not current enhancer baseline evidence.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, major state ownership or newest artifact/baseline changes.