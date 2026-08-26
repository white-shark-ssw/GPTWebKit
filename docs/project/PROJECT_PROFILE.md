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
  - `Diagnostics/CEConversationIdentityTrace` — optional sanitized runtime correlation trace; alpha53 also records bounded structural `REFRESH-PATH` call-site/navigation evidence for exact init/prepare/detail host requests. It is not identity authority.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger and remove it after the candidate build.
- **Newest enhancer artifact**: `0.1.0-alpha53-refresh-path-trace`; Actions `33007145536`, job `98303728684`; package id `9621009139`, dylib id `9621009533`.
- **Current validation**: alpha53 = **Code written → CI passed → Artifact produced; Runtime/manual pending**. It is diagnostic-only and keeps alpha52 production Sync/Reload semantics unchanged.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains separate; recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` names must match.
- **Current recognition candidate**: `0.1.0-alpha53-refresh-path-trace`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment contracts

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app; compiler target `arm64-apple-ios17.0`.
- **Auth/request context**: host auth/account/request templates remain memory-only.
- **Identity**: exact foreground identity is semantic/source-aware. Generic/background request recency, arbitrary UIKit/menu UUIDs and title-only matching are not authority. The validated explicit `conversation/init` body ID updates the sole `CEConversationContext`; current-chat menu actions freeze that ID.
- **Sync**: `同步最新消息` makes one guarded enhancer GET for the exact target. HTTP 429 is not automatically retried. GET success is server-state evidence only, not visible synchronization.
- **Refresh handoff**: same-ID host request delivery is not Reload completion. Alpha52 reports it as a refresh request and does not repeat route delivery after request delivery is proven solely because the UI did not rebuild. UI success still requires actual refresh/rebuild evidence.
- **Genuine navigation evidence**: alpha52 A→B→A runtime trace shows exact host navigation emits exact `conversation/init`, then within about 125 ms exact `prepare` + conversation detail GET (+ another prepare). This traffic is evidence of a host navigation-state transition; it is not authorization/proof that replaying the same network requests would refresh UI.
- **Sidebar management**: non-current Rename/Export resolve the selected row independently from current context; duplicate titles require explicit selection.
- **Rename**: current-menu Rename uses the frozen exact ID and rechecks it immediately before PATCH.
- **Rate limiting**: HTTP 429 is server-side throttling; short-window bursts are a plausible trigger but exact account/IP/endpoint thresholds are undocumented. Enhancer code must not amplify 429 with burst retries.
- **Project-title presentation**: exact current title may be used only after identity is proven. The existing UIKit label-pair strategy is runtime-rejected on app `1.2026.202`; user has paused this work.
- **Generation recovery**: a page refresh/rebuild does not prove an interrupted response stream recovered. No speculative `/resume`, generation retry or watchdog is authorized without runtime evidence.
- **Diagnostic persistence**: sanitized user-started identity traces may include conversation IDs/titles and structural request/menu/UI metadata. Alpha53 additionally permits bounded structural view-controller/navigation class data and sanitized call-stack symbols for exact init/prepare/detail requests. Authorization, cookies, account IDs, raw request templates, full headers/bodies and message contents remain prohibited.

## Current evidence

- Base branch `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Alpha46 established explicit `conversation/init` semantic identity and rejected arbitrary menu UUIDs.
- Alpha50 established exact identity/title acquisition while rejecting the project-header UILabel target.
- Alpha51 trace `60CF506D-C2A9-4E8A-8A96-B01E1FD8FD70` proved three same-ID custom-route deliveries could produce detail GETs with no visible page rebuild.
- Alpha52 trace `585B0B11-C85D-4A19-BA16-4F55D56A320A` captured genuine A→B→A and proves exact navigation includes init→prepare→detail traffic absent from the failed same-current route path.
- Alpha53 build/test source `b62878928816c40cbed8c11847a3ed7ae494adde`; Actions `33007145536`; CI bookkeeping `fa926ca61013292056e647f78d1d1677b608a72b`; cleanup head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53` differs from tested source only by run-id bookkeeping and trigger cleanup.
- Alpha53 package digest `sha256:500a38652acf60b50f15f5ace41ca31e68a198cda3acaf724f1547f88bbeb6b2`; dylib Actions archive digest `sha256:5648a23263eb0d7fa535387a5f7fcbe2d8622142f0bdfd862515be32bb7d59a8`; extracted dylib sha256 `78a38421fe04adba9774bb8e42947ea48120d2a61698359f04c31bdb6f6f86a2`.

## Auto-refresh rule

Update this file proactively when project purpose, stack, build/test commands, candidate/version scheme, deployment/runtime, ownership, artifact or accepted-baseline truth changes.