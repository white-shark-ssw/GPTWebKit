# Project Profile

## Initialization

**Initialized** — 2026-08-25 from real repository evidence. Unknown facts remain `Unknown / Unverified`.

## Identity

- **Project name**: `GPTWebKit` repository; current active product track is `ChatGPTEnhancer`.
- **Repository**: `white-shark-ssw/GPTWebKit`.
- **Project purpose**: iOS tooling that augments ChatGPT usage. The active track injects a dylib into the official ChatGPT iOS app to add conversation export/management/sync/reload/diagnostic UI and exact-current-conversation-aware behavior. Older branches contain standalone/native ChatGPT utility and WebView experiments.
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
  - `Core/CEContextResolver` — compatibility getter for current exact context; the old periodic UIKit/title resolver is retired.
  - `Network/CENetworkObserver` — official-network observation/template/events/catalog input. Generic observed request IDs are passive; only the specifically validated explicit `POST /backend-api/conversation/init` request-body conversation ID may promote foreground identity into the existing context owner.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner. Alpha51 makes HTTP 429 terminal for the current request instead of automatically retrying it.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog and presentation title owner.
  - `UI/CEEnhancerUI` — host UIKit integration, immutable exact current-header Sync/Reload/Rename/Export actions, row-scoped sidebar Rename/Export, and paused project-header presentation code.
  - `UI/CEConversationUIReloadEvidence` — public-UIKit ephemeral current-message-view snapshot/rebuild evidence for manual Reload completion; not an identity owner.
  - `Export/CEMarkdownExporter` — Markdown generation.
  - `Features/*` — exact-ID Sync/Rename/Reload/recovery behavior.
  - `Diagnostics/CEConversationIdentityTrace` — optional persistent sanitized menu/network/Share/UI-structure evidence recorder; not an identity authority.
  - other `Diagnostics/*` — runtime probes/recovery diagnostics.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger for one CI candidate and remove it afterward.
- **Newest enhancer artifact**: `0.1.0-alpha51-sync-latest-rate-limit`; Actions `33000977913`, job `98282430781`; package id `9618537159`, dylib id `9618537770`.
- **Current validation**: alpha51 = **Code written → CI passed → Artifact produced; Runtime/manual pending**. It renames current Pull to Sync, removes automatic 429 retry, guards concurrent Sync GETs, and hands a finished same-ID server result into the existing exact-current Reload path. Runtime behavior is not accepted until device-tested.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains a separate Active candidate stacked on older recognition source. Current recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` artifact/package names must match.
- **Current recognition candidate**: `0.1.0-alpha51-sync-latest-rate-limit`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app.
- **Compiler target**: `arm64-apple-ios17.0`.
- **Auth/request context**: host authentication/account/request templates remain memory-only.
- **Current identity rule**: exact foreground identity is semantic/source-aware. Generic/background conversation request recency, arbitrary UIKit/menu UUIDs and title-only matching are not authority. The validated explicit `conversation/init` body ID updates the sole `CEConversationContext`; the top-right current-chat menu freezes that exact ID for Sync/Reload/Rename/Export.
- **Sync Latest rule**: `同步最新消息` makes one guarded enhancer GET for the frozen exact current ID. HTTP 429 is not automatically retried. If server state is still generating, do not force a refresh. If the latest result is finished and current ID is unchanged, hand off to existing exact-current Reload; the GET itself is not UI synchronization success.
- **Sidebar management rule**: non-current conversation-list Rename/Export must resolve the selected row independently from current context. Alpha50/51 use row/menu presentation title only to produce a `CECatalog` candidate set; duplicate titles require explicit selection and no arbitrary menu UUID is identity.
- **Rename rule**: current-menu Rename uses the frozen exact ID and rechecks the same context again immediately before PATCH execution; a title or source-view candidate cannot choose the current-chat rename target.
- **Reload completion rule**: observing a same-ID official request proves delivery, not completion. A Reload success message also requires current conversation UI rebuild/refresh evidence; runtime acceptance remains pending.
- **Rate-limit rule**: HTTP 429 is a server-side rate-limit response. Short-window request bursts are a plausible trigger, but exact account/IP/endpoint thresholds are undocumented. Enhancer code must not amplify a 429 with automatic burst retries.
- **Presentation-title rule**: the exact current-chat official menu/catalog title may be used only for presentation after identity is already proven. Alpha50 rejected the existing UIKit `聊天` + nearby title `UILabel` strategy on app `1.2026.202`; user has paused this work.
- **Generation recovery rule**: page reload/rebuild does not prove a previously interrupted generation recovered. No speculative resume/retry/watchdog is authorized without a trace that captures the host lifecycle from before prompt send/disconnect.
- **Diagnostic persistence exception scope**: user-started sanitized identity correlation data may persist conversation IDs/titles plus structural menu/request/UI metadata. Authorization, cookies, account IDs, raw request templates, full headers, raw bodies and message contents remain prohibited.

## Documentation evidence

- Base branch remains `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked before alpha51 on 2026-08-27.
- Alpha46 runtime trace established exact semantic identity evidence and invalidated arbitrary menu UUID identity.
- Alpha50 runtime trace `A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9` proves exact current identity/title acquisition while rejecting the current UIKit UILabel project-header target assumption.
- Alpha51 build/test source `bbc8696d7c11f2d6030d7e44cdc3c979f38dba77`; Actions `33000977913`; CI bookkeeping `798631ce879dd32e5f774659789d03c3772ad1f5`; post-CI head `8722e5f2a0a7bd6513997825b1a25991e5d342b7` differs from tested source only by run-id bookkeeping and removal of the temporary branch trigger.
- Alpha51 package digest `sha256:8b72320f471e540d679a4b79899659e43250c79543ce0a68b7bb76c70b6267cc`; dylib Actions archive digest `sha256:fd94fc813723cdef6067930e4a512da3155f2e6f78bae6c0ea0d3ec7e0385e16`; extracted dylib sha256 `2ccc4108373b5ede6c14bfba5057ceed08354b53b934ea493ae5e413e4be3ccf`.
- Legacy tracks remain separate and are not current enhancer baseline evidence.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, major state ownership or newest artifact/baseline changes.