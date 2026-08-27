# Project Profile

## Initialization

**Initialized** — 2026-08-25 from real repository evidence. Unknown facts remain `Unknown / Unverified`.

## Identity

- **Project name**: `GPTWebKit`; current active product track is `ChatGPTEnhancer`.
- **Repository**: `white-shark-ssw/GPTWebKit`.
- **Project purpose**: iOS tooling that augments the official ChatGPT app with exact-current-conversation-aware export, management, Sync/Reload and diagnostic behavior. Older branches contain standalone/native and WebView experiments.
- **Product type**: current track — injected iOS dynamic library / host-app enhancer.
- **Primary runtime**: official ChatGPT iOS bundle `com.openai.chat`, iOS 17.0+, plain dylib injection such as TrollFools / 巨魔注入器.

## Technology stack

- **Primary languages**: Objective-C++ (`.mm`) for `ChatGPTEnhancer`; Swift for legacy/native `GPTWebKit`; Bash for packaging; YAML for GitHub Actions.
- **Frameworks**: UIKit, Foundation, QuartzCore, CoreGraphics.
- **Third-party package manager**: none verified for the enhancer; `Unknown / Unverified` beyond Apple frameworks.
- **Important configs**: `ChatGPTEnhancer/Support/ChatGPTEnhancer.plist`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml`.

## Repository structure / state owners

- **Current source root**: `ChatGPTEnhancer/Sources/`; legacy app root `GPTWebKit/`.
- **Startup owner**: `Bootstrap/CEBootstrap.mm`.
- **Tests**: no automated unit/UI test root verified.
- **Key owners**:
  - `Core/CECore` / `CEConversationContext` — shared helpers and sole long-lived active-conversation identity authority.
  - `Network/CENetworkObserver` — passive official-network observation/template/events/catalog input. Generic observed request IDs are not foreground authority; only validated explicit exact `POST /backend-api/conversation/init` body `conversation_id` may promote foreground identity.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current request rather than an automatic burst retry.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog.
  - `UI/CEEnhancerUI` — current exact-ID menu integration, row-scoped sidebar Rename/Export and paused project-header presentation code.
  - `UI/CEConversationUIReloadEvidence` — ephemeral public-UIKit UI refresh/rebuild proof; alpha57 accepts active attached navigation-controller object replacement in addition to scroll/anchor replacement evidence.
  - `Export/CEMarkdownExporter` — Markdown generation from complete conversation data.
  - `Features/*` — exact-ID Sync/Rename/Reload/recovery behavior.
  - `Diagnostics/*` — optional sanitized runtime correlation evidence, never identity authority.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger and remove it after the candidate build.
- **Newest enhancer artifact**: `0.1.0-alpha57-navigation-rebuild-proof`; Actions `33083945220`, job `98558346397`; package id `9651296956`, dylib id `9651298129`.
- **Current validation**: alpha57 = **Code written → CI passed → Artifact produced; Runtime/manual pending**. Nothing Stable/Frozen.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains separate; recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` names must match.
- **Current recognition candidate**: `0.1.0-alpha57-navigation-rebuild-proof`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment contracts

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app; compiler target `arm64-apple-ios17.0`.
- **Auth/request context**: host auth/account/request templates remain memory-only.
- **Identity**: exact foreground identity is semantic/source-aware. Generic/background request recency, arbitrary UIKit/menu UUIDs and title-only matching are not authority. The validated explicit exact `conversation/init` body ID updates the sole `CEConversationContext`; current-chat menu actions freeze that ID.
- **Sync**: `同步最新消息` makes one guarded enhancer GET for the exact target. HTTP 429 is not automatically retried. GET success is server-state evidence only, not visible synchronization.
- **Refresh handoff**: request delivery is not completion. Visible success requires exact same-ID request evidence plus UI refresh/rebuild evidence.
- **Alpha57 UI proof**: real-device alpha56 trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D` proved a user-visible refresh can replace active attached navigation controller `nav-1` with a different active attached `nav-2` while exact same-ID init/prepare/detail occurs. Alpha57 therefore treats active attached navigation-controller object replacement as ephemeral UI rebuild evidence. The object identity is not persisted and is not conversation identity.
- **Existing UI proof retained**: conversation scroll-view object replacement and substantial visible-anchor turnover remain independent rebuild signals.
- **Navigation mutation rule**: evidence that the host replaced a navigation controller does not authorize the enhancer to call `setViewControllers`, push, pop or force stack shape.
- **Sidebar management**: non-current Rename/Export resolve the selected row independently from current context; duplicate titles require explicit selection.
- **Rename**: current-menu Rename uses the frozen exact ID and rechecks it immediately before PATCH.
- **Rate limiting**: HTTP 429 is server-side throttling; short-window bursts are a plausible trigger but exact account/IP/endpoint thresholds are undocumented. Enhancer code must not amplify 429 with burst retries.
- **Project-title presentation**: existing UIKit label-pair strategy is runtime-rejected on app `1.2026.202`; user has paused this work.
- **Generation recovery**: a page refresh/rebuild does not prove an interrupted response stream recovered. No speculative `/resume`, generation retry or watchdog is authorized without runtime evidence.
- **Diagnostic persistence**: sanitized user-started identity traces may include conversation IDs/titles, structural request/menu/UI metadata, bounded controller/navigation class names and sanitized call-stack symbols. Authorization, cookies, account IDs, raw request templates, full headers/bodies and message contents remain prohibited.

## Current evidence

- Base branch `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Alpha46 established explicit `conversation/init` semantic identity and rejected arbitrary menu UUIDs.
- Alpha51 removed automatic 429 burst retries and established Sync server-fetch semantics.
- Alpha52–55 established that genuine host navigation state precedes init/prepare/detail and that custom-route state differs from normal push/pop navigation.
- Alpha56 runtime proved the custom route can replace the active attached navigation-controller instance and visibly refresh the page while the old scroll/anchor detector false-negatives.
- Alpha57 build/test source `fe48c56350720127786670d9fe37e28280905055`; Actions `33083945220`; CI bookkeeping `ef75624e24e60842afabde93f4151a39453f1c9f`; cleanup head `ad4a4718c498a9926ed553797ac9fb3e45df48c4` differs from tested source only by run-id bookkeeping and trigger cleanup.
- Alpha57 package digest `sha256:c71bfab996a1f01a0634701b95bafb12111863dcc97e3bb4469728e567630cae`; dylib Actions archive digest `sha256:ccf2275eded12bd180741ef82d3685b1be21a8da33c8cf01c8b9cea823755fe3`; extracted dylib sha256 `2d7de7f8b424d62ba970bf8913da5b0f64ed11d60108d06db5a3b2a9b62a8a3d`.

## Auto-refresh rule

Update this file proactively when project purpose, stack, build/test commands, candidate/version scheme, deployment/runtime, ownership, artifact or accepted-baseline truth changes.