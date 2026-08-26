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
  - `Core/CEContextResolver` — compatibility getter; old periodic UIKit/title identity resolver is retired.
  - `Network/CENetworkObserver` — passive official-network observation/template/events/catalog input. Generic observed request IDs are not foreground authority; only the validated explicit `POST /backend-api/conversation/init` body `conversation_id` may promote foreground identity.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current request rather than an automatic burst retry.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog.
  - `UI/CEEnhancerUI` — current exact-ID menu integration, row-scoped sidebar Rename/Export and paused project-header presentation code.
  - `UI/CEConversationUIReloadEvidence` — ephemeral public-UIKit UI refresh/rebuild proof; not identity authority.
  - `Export/CEMarkdownExporter` — Markdown generation from complete conversation data.
  - `Features/*` — exact-ID Sync/Rename/Reload/recovery behavior.
  - `Diagnostics/CEConversationIdentityTrace` — optional sanitized runtime correlation trace; not identity authority.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger and remove it after the candidate build.
- **Newest enhancer artifact**: `0.1.0-alpha52-sync-refresh-handoff`; Actions `33004675627`, job `98295074960`; package id `9620028731`, dylib id `9620029383`.
- **Current validation**: alpha52 = **Code written → CI passed → Artifact produced; Runtime/manual pending**. It corrects Sync/Reload refresh-request wording and stops repeated exact-route delivery after same-ID request delivery is already proven without a UI rebuild. It does not claim to have found a genuine host-side refresh mechanism.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains separate; recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` names must match.
- **Current recognition candidate**: `0.1.0-alpha52-sync-refresh-handoff`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment contracts

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app; compiler target `arm64-apple-ios17.0`.
- **Auth/request context**: host auth/account/request templates remain memory-only.
- **Identity**: exact foreground identity is semantic/source-aware. Generic/background request recency, arbitrary UIKit/menu UUIDs and title-only matching are not authority. The validated explicit `conversation/init` body ID updates the sole `CEConversationContext`; current-chat menu actions freeze that ID.
- **Sync**: `同步最新消息` makes one guarded enhancer GET for the exact target. HTTP 429 is not automatically retried. GET success is server-state evidence only, not visible synchronization.
- **Refresh handoff**: same-ID host request delivery is not Reload completion. Alpha52 reports it as a refresh request and does not repeat route delivery after request delivery is proven solely because the UI did not rebuild. UI success still requires actual refresh/rebuild evidence.
- **Sidebar management**: non-current Rename/Export resolve the selected row independently from current context; duplicate titles require explicit selection.
- **Rename**: current-menu Rename uses the frozen exact ID and rechecks it immediately before PATCH.
- **Rate limiting**: HTTP 429 is server-side throttling; short-window bursts are a plausible trigger but exact account/IP/endpoint thresholds are undocumented. Enhancer code must not amplify 429 with burst retries.
- **Project-title presentation**: exact current title may be used only after identity is proven. The existing UIKit label-pair strategy is runtime-rejected on app `1.2026.202`; user has paused this work.
- **Generation recovery**: a page refresh/rebuild does not prove an interrupted response stream recovered. No speculative `/resume`, generation retry or watchdog is authorized without runtime evidence.
- **Diagnostic persistence**: sanitized user-started identity traces may include conversation IDs/titles and structural request/menu/UI metadata; Authorization, cookies, account IDs, raw request templates, full headers/bodies and message contents remain prohibited.

## Current evidence

- Base branch `feat/chatgpt-enhancer-v0.1` remained `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` at alpha52 preflight.
- Alpha46 established explicit `conversation/init` semantic identity and rejected arbitrary menu UUIDs.
- Alpha50 trace established exact identity/title acquisition while rejecting the project-header UILabel target.
- Alpha51 trace `60CF506D-C2A9-4E8A-8A96-B01E1FD8FD70` proved three same-ID custom-route deliveries could produce detail GETs with no visible page rebuild; this is the runtime basis for alpha52.
- Alpha52 build/test source `9c06219cdee1ac00b75372f1480278169b3f6e59`; Actions `33004675627`; CI bookkeeping `087d03884b6a4c565d126e8c90849bafa0bf28e9`; cleanup head `90c5bb97f332b2c0c4935ad3eaea9432df3e156e` differs from tested source only by run-id bookkeeping and trigger cleanup.
- Alpha52 package digest `sha256:7fa4de42d8276e66934b4d4b2551ddf0f0916a069446388a6af4ae657140c075`; dylib Actions archive digest `sha256:dc87efcc450d5b26a9588606999cea1c481ff7ac33da51d57a88da47eea198ae`; extracted dylib sha256 `0b19bb2ec6d2b9a5ff26210bbd8d8945cffa77bb280b38e28ef1e0f9dc7f62d5`.

## Auto-refresh rule

Update this file proactively when project purpose, stack, build/test commands, candidate/version scheme, deployment/runtime, ownership, artifact or accepted-baseline truth changes.