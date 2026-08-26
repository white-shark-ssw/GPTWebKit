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
  - `Core/CECore` / `CEConversationContext` — shared helpers and sole active-conversation state authority.
  - `Core/CEContextResolver` — resolves active conversation from currently visible UIKit/catalog-backed evidence; no generic network task owns foreground identity.
  - `Network/CENetworkObserver` — passive official-network observation, request templates/events/project/catalog input. Observed request conversation IDs do not mutate active identity.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog.
  - `UI/CEEnhancerUI` — host UIKit integration, floating-tool lifecycle and action-time visible-conversation verification. Floating-button visibility is intentionally independent of identity proof in alpha45.
  - `Export/CEMarkdownExporter` — Markdown generation.
  - `Features/*` — pull/rename/reload/recovery; Pull and manual Reload independently require fresh visible proof.
  - `Diagnostics/*` — runtime probes/recovery diagnostics.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger remains `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger for CI and remove it afterward.
- **Newest enhancer artifact**: `0.1.0-alpha45-visible-button-guard`; Actions run `32939338703`, job `98086902604`; package id `9595962373`, dylib id `9595962949`. Runtime/manual acceptance pending.
- **Rejected previous artifact**: alpha44 passed CI but failed real-device usability because the floating button disappeared when identity was not yet proven. Alpha42 previously failed real-device recognition because Pull/Reload could cross conversations after extended use.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and is stacked on rejected alpha42 recognition; it is not an accepted recognition baseline.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` artifact/package names must match.
- **Current recognition candidate**: `0.1.0-alpha45-visible-button-guard`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app.
- **Compiler target**: `arm64-apple-ios17.0`.
- **Auth/request context**: host authentication/account/request templates remain memory-only.
- **Current identity safety rule**: background/observed conversation requests are not foreground identity authority. Current-conversation actions must fail closed when current visible identity cannot be uniquely proven.
- **Floating entry rule**: floating-tool visibility is UI availability only, not current-conversation proof; the entry point may remain visible while guarded actions refuse due to unknown/ambiguous identity.

## Documentation evidence

- Base branch remains `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` as rechecked 2026-08-26.
- Alpha42 runtime failure: user real-device result 2026-08-26, recorded in `PROJECT_STATE`, checkpoint and `BUILD_TEST_INDEX`.
- Alpha44 runtime failure: user real-device result 2026-08-26, floating button missing due to ID-gated visibility.
- Alpha45 source/build: Draft PR #2; build/test source `037b4aba99b45f30e04a8f9714231a545a0137c2`; Actions `32939338703`; package digest `sha256:04e46a8f48643fee95968161798b74a8cb7b963beeadc0e2fab14a339fbeb839`; dylib digest `sha256:7868dbe9a0ba84ae0985bb8cea2c136640a5b6c13e7b1b5596a11982e2e97c59`.
- Legacy tracks remain separate and are not current enhancer baseline evidence.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, major state ownership or newest artifact/baseline changes.
