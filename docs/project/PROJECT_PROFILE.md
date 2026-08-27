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
  - `Network/CENetworkObserver` — passive official-network observation/template/events/catalog input and existing NSURLSession hook owner. Generic observed request IDs are not foreground authority; only validated explicit exact `POST /backend-api/conversation/init` body `conversation_id` may promote foreground identity.
  - `Network/CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current request rather than an automatic burst retry.
  - `Storage/CECatalog` — conversation ID/title/update-time/project catalog.
  - `UI/CEEnhancerUI` — current exact-ID menu integration, row-scoped sidebar Rename/Export and paused project-header presentation code.
  - `UI/CEConversationUIReloadEvidence` — ephemeral public-UIKit UI refresh/rebuild proof; not identity authority.
  - `Export/CEMarkdownExporter` — Markdown generation from complete conversation data.
  - `Features/*` — exact-ID Sync/Rename/Reload/recovery behavior.
  - `Diagnostics/CEConversationIdentityTrace` — optional sanitized runtime correlation trace; alpha55 established passive public navigation-mutation correlation.
  - `Diagnostics/CENavigationInstanceTrace` — alpha56 evidence-only public navigation-controller instance/attachment snapshotting around same-current refresh handoff; stable per-process diagnostic tokens are not identity authority.

## Build and validation

- **Build command**: `bash ./ChatGPTEnhancer/build.sh` on macOS/Xcode/iPhoneOS SDK.
- **Test command**: no automated test command verified.
- **Lint/static checks**: no dedicated suite verified.
- **Enhancer CI**: `.github/workflows/build-enhancer.yml`, macOS 15. Normal push trigger is `feat/chatgpt-enhancer-v0.1`; isolated candidate branches temporarily add their own trigger and remove it after the candidate build.
- **Newest enhancer artifact**: `0.1.0-alpha56-navigation-instance-trace`; accepted Actions `33052999411`, job `98452810620`; package id `9638389331`, dylib id `9638389813`.
- **Current validation**: alpha56 = **Code written → CI passed → Artifact produced; Runtime/manual pending**. First alpha56 CI attempt `33052810815` failed compile due a corrected diagnostic-only syntax typo and produced no artifact.
- **Parallel artifact**: alpha43 belongs to `DEV-conversation-usage` and remains separate; recognition work does not modify percentage-owned source.

## Versioning and candidate identity

- **Enhancer version source**: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`.
- **Duplicated identity locations**: `CECore.mm`, `ChatGPTEnhancer/build.sh`, `.github/workflows/build-enhancer.yml` names must match.
- **Current recognition candidate**: `0.1.0-alpha56-navigation-instance-trace`.
- **Build number**: no separate product build number verified; Actions run ID is build evidence only.
- **Release/tag scheme**: no formal release/tag process verified.
- **Parallel rule**: each Active dev task owns a unique candidate/artifact identity.

## Runtime / deployment contracts

- **Platform**: arm64 iOS 17.0+ inside official ChatGPT iOS app; compiler target `arm64-apple-ios17.0`.
- **Auth/request context**: host auth/account/request templates remain memory-only.
- **Identity**: exact foreground identity is semantic/source-aware. Generic/background request recency, arbitrary UIKit/menu UUIDs and title-only matching are not authority. The validated explicit exact `conversation/init` body ID updates the sole `CEConversationContext`; current-chat menu actions freeze that ID.
- **Sync**: `同步最新消息` makes one guarded enhancer GET for the exact target. HTTP 429 is not automatically retried. GET success is server-state evidence only, not visible synchronization.
- **Refresh handoff**: same-ID host request delivery is not Reload completion. Alpha52+ reports it as a refresh request and does not repeat route delivery after request delivery is proven solely because the UI did not rebuild. UI success still requires actual refresh/rebuild evidence.
- **Genuine navigation evidence**: alpha52/53 established exact init→prepare/detail correlation after host navigation. Alpha54 strengthened structural staging at navigation depth 2 before exact target depth 3. Alpha55 then directly observed genuine public navigation mutation as `pop 3→2` followed by `push 2→3`, with stable callers and exact target init ~128–135 ms after the target push.
- **Same-current custom-route evidence**: alpha55 observed a structurally different `setViewControllers: 0→1` path. In that trace the route subsequently emitted exact init/prepare/detail at depth 1 but still produced no visible page rebuild. Therefore init/prepare/detail remains consequence/evidence and is not sufficient refresh authority.
- **Navigation-instance uncertainty**: alpha55 did not record navigation-controller object identity/attachment. Whether custom-route `0→1` is a new/off-path instance or an active host instance remains `Unknown / Unverified`; alpha56 exists specifically to resolve that uncertainty.
- **Rejected network-creation hypothesis**: alpha54 emitted zero `REFRESH-CREATE` records despite semantic request observations, so the relevant official requests bypass the specifically swizzled Objective-C NSURLSession task-creation selectors in that runtime. The exact higher-level Foundation/Swift path remains `Unknown / Unverified`.
- **Alpha56 navigation diagnostic**: each observed public `UINavigationController` receives a stable per-process diagnostic token without raw pointer persistence. Around same-current route handoff, snapshots record bounded stack composition, visible controller class, foreground-window attachment, key-window status, active-nav relation and bounded parent/presentation class metadata. This is observation only and does not mutate navigation.
- **Navigation evidence rule**: navigation count/composition, mutation caller traces and instance/attachment snapshots are diagnostic evidence only. Do not restore a three-controller stack, push/pop controllers, set view controllers, or hard-code observed Swift controller classes without separate production evidence.
- **Sidebar management**: non-current Rename/Export resolve the selected row independently from current context; duplicate titles require explicit selection.
- **Rename**: current-menu Rename uses the frozen exact ID and rechecks it immediately before PATCH.
- **Rate limiting**: HTTP 429 is server-side throttling; short-window bursts are a plausible trigger but exact account/IP/endpoint thresholds are undocumented. Enhancer code must not amplify 429 with burst retries.
- **Project-title presentation**: exact current title may be used only after identity is proven. The existing UIKit label-pair strategy is runtime-rejected on app `1.2026.202`; user has paused this work.
- **Generation recovery**: a page refresh/rebuild does not prove an interrupted response stream recovered. No speculative `/resume`, generation retry or watchdog is authorized without runtime evidence.
- **Diagnostic persistence**: sanitized user-started identity traces may include conversation IDs/titles, structural request/menu/UI metadata, bounded controller/navigation class names, public navigation selector names, per-process non-pointer nav tokens, attachment/active flags, observation-source labels and sanitized call-stack symbols. Authorization, cookies, account IDs, raw request templates, full headers/bodies, raw pointer addresses and message contents remain prohibited.

## Current evidence

- Base branch `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Alpha46 established explicit `conversation/init` semantic identity and rejected arbitrary menu UUIDs.
- Alpha50 established exact identity/title acquisition while rejecting the project-header UILabel target.
- Alpha51 trace proved repeated same-current route deliveries could produce detail GETs with no visible rebuild.
- Alpha52 trace captured genuine A→B→A and established init→prepare→detail as host-navigation evidence.
- Alpha53 confirmed one-delivery suppression, genuine navigation depth 3 versus failed same-current depth 1, and the limitation of downstream call-stack sampling.
- Alpha54 trace `1995A79E-71DF-4EBC-BB1E-A61D48871FD2` recorded ID-less staging at nav depth 2, exact navigation at depth 3, failed same-current detail at depth 1 and zero `REFRESH-CREATE`; this rejected the selected Objective-C task-creation-selector path.
- Alpha55 trace `F042014D-8407-4910-A5DA-2A9399C26425` observed stable genuine `pop 3→2 / push 2→3` mutation versus custom-route `setViewControllers 0→1`; the latter could still emit exact init/prepare/detail but did not visibly rebuild the page.
- Alpha56 accepted build/test source `f2cee73312da7254d44053ec092f9e7643326d92`; Actions `33052999411`; CI bookkeeping `6b69425e5c2284777b86890d0d967f1d3c45dcf5`; cleanup head `ce9bf42d6c4d3afde125e01c03120adbdf6f718d` differs from tested source only by run-id bookkeeping and trigger cleanup.
- Alpha56 package digest `sha256:c6eab9030b6b4d9b5957fbb864410d0bf0931785ee95d4d4ca098e8d13dae0fb`; dylib Actions archive digest `sha256:993c966dd8dbdcc7ceb805d8ad647df5b0dff0a06b97e31b61923792a89d9266`; extracted dylib sha256 `3af11e471dd986d7074619be4f0b224f28e90ec3b29c73dd31379f4bb37b3b42`.

## Auto-refresh rule

Update this file proactively when project purpose, stack, build/test commands, candidate/version scheme, deployment/runtime, ownership, artifact or accepted-baseline truth changes.