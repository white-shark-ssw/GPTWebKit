# Project Profile

## Initialization

**Initialized** — 2026-08-25 from real repository evidence. Unknown facts remain `Unknown / Unverified`.

## Identity

- **Project name**: `GPTWebKit` repository; current active product track is `ChatGPTEnhancer`.
- **Repository**: `white-shark-ssw/GPTWebKit`.
- **Project purpose**: iOS tooling that augments ChatGPT usage. The active track injects a dylib into the official ChatGPT iOS app to add conversation export/management/reload/diagnostic UI and current-conversation-aware behavior. Older branches contain standalone/native ChatGPT utility and WebView experiments.
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
  - `Core/CEContextResolver` — resolves active conversation from currently visible UIKit/catalog-backed evidence; generic network task resume does not own foreground identity.
  - `Network/CENetworkObserver` — passive official-network observation, request templates/events/project/catalog input; alpha46 additionally emits sanitized trace evidence but observed request IDs still do not mutate active identity.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog.
  - `UI/CEEnhancerUI` — host UIKit integration, menu augmentation, floating-tool lifecycle and current action entry surfaces.
  - `Export/CEMarkdownExporter` — Markdown generation.
  - `Features/*` — pull/rename/reload/recovery; current Pull/Reload remain fail-closed while alpha46 records proof/target evidence.
  - `Diagnostics/CEConversationIdentityTrace` — experimental persistent sanitized menu/network/Share identity evidence recorder; not an identity authority.
  - other `Diagnostics/*` — runtime probes/recovery diagnostics.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger remains `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger for one CI candidate and remove it afterward.
- **Newest enhancer artifact**: `0.1.0-alpha46-conversation-identity-trace`; Actions run `32950198256`, job `98119660626`; package id `9599824714`, dylib id `9599825427`. Runtime/manual trace validation pending.
- **Previous recognition evidence**: alpha45 is not accepted because current project chat can still false-negative on exact visible proof; alpha44 rejected due missing floating button; alpha42 rejected due real-device cross-conversation Pull/Reload.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and is stacked on rejected alpha42 recognition; it is not an accepted recognition baseline.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` artifact/package names must match.
- **Current recognition candidate**: `0.1.0-alpha46-conversation-identity-trace`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app.
- **Compiler target**: `arm64-apple-ios17.0`.
- **Auth/request context**: host authentication/account/request templates remain memory-only.
- **Current identity safety rule**: background/observed conversation requests are not foreground identity authority. Current-conversation actions must not use stale cached IDs when current exact target is unproven.
- **Diagnostic persistence exception scope**: alpha46 may persist only explicitly user-started sanitized identity correlation data (conversation IDs/titles plus structural menu/request metadata). Authorization, cookies, account IDs, raw request templates, full headers, raw bodies and message contents remain prohibited from persistence.

## Documentation evidence

- Base branch remains `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` as rechecked 2026-08-26.
- Alpha45 runtime evidence: user screenshot/recording 2026-08-26 shows Reload false-negative while menu-scoped enhancer Rename resolves the correct title.
- Share evidence: user screenshot 2026-08-26 shows official `共享指向聊天的链接` UI tied to current chat title; exact ID source remains under investigation.
- Alpha46 source/build: Draft PR #2; build/test source `fc78d7d525969699fbd15a3f180e563e93e6d424`; Actions `32950198256`; package digest `sha256:0e8a35affb33f7f1b359dfb9e62c5ddaf95e5f72e3c3b198dedf496050ba32b9`; dylib digest `sha256:61de097c001094c512d651825df2d904369911443a032787e349192c3c4e9e95`; post-CI cleanup head `96d845e7d750ea178ff73c12faed115dff33d14c` differs only by run-id bookkeeping/workflow trigger cleanup.
- Legacy tracks remain separate and are not current enhancer baseline evidence.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, major state ownership or newest artifact/baseline changes.