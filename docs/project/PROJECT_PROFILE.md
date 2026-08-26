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
  - `Core/CEContextResolver` — resolves active conversation from currently visible UIKit/catalog-backed evidence; alpha44 no longer derives active identity from generic network task resume.
  - `Network/CENetworkObserver` — passive official-network observation, request templates/events/project/catalog input. Alpha44 explicitly removes observed-request conversation IDs as foreground identity writes.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog.
  - `UI/CEEnhancerUI` — host UIKit integration and action-time visible-conversation verification.
  - `Export/CEMarkdownExporter` — Markdown generation.
  - `Features/*` — pull/rename/reload/recovery; Pull and manual Reload now independently require fresh visible proof in alpha44.
  - `Diagnostics/*` — runtime probes/recovery diagnostics.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger remains `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger for CI and remove it afterward.
- **Newest enhancer artifact**: `0.1.0-alpha44-current-conversation-guard`; Actions run `32937976994`, job `98082904535`; package id `9595516821`, dylib id `9595517523`. Runtime/manual acceptance pending.
- **Rejected previous artifact**: alpha42 passed CI but failed real-device recognition: Pull/Reload could cross conversations after extended use. Header title override also had no visible effect.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and is stacked on rejected alpha42 recognition; it is not an accepted recognition baseline.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` artifact/package names must match.
- **Current recognition candidate**: `0.1.0-alpha44-current-conversation-guard`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app.
- **Compiler target**: `arm64-apple-ios17.0`.
- **Auth/request context**: host authentication/account/request templates remain memory-only.
- **Current identity safety rule**: background/observed conversation requests are not foreground identity authority. Current-conversation actions must fail closed when current visible identity cannot be uniquely proven.

## Documentation evidence

- Base branch remains `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` as rechecked 2026-08-26.
- Alpha42 runtime failure: user real-device result 2026-08-26, recorded in `PROJECT_STATE`, checkpoint and `BUILD_TEST_INDEX`.
- Alpha44 source/build: Draft PR #2; build/test source `668540cbabf300d08c929a1daa057ea4959f2f01`; Actions `32937976994`; package digest `sha256:c084a7e6bce60d4df0a7378ae351b75a2de0669d898fd5f9a019e504c791eb99`; dylib digest `sha256:e36cfdd0571b9ee34fb629e58f066947b231602194c2a1301b17c5ab2a28c7a9`.
- Legacy tracks remain separate and are not current enhancer baseline evidence.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, major state ownership or newest artifact/baseline changes.
