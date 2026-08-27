# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` rechecked unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` remained open/draft/mergeable before alpha54 edits.
- Parallel `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Alpha54 did not modify percentage-owned sources/checkpoint.
- No product module is Frozen. Diagnostics and Network are Active. `CENetworkObserver` was changed only at its existing NSURLSession task-creation hooks to invoke diagnostic logging; request ownership and production traffic behavior remain unchanged.
- Candidate `ENH-0.1.0-alpha54-task-creation-trace` / `0.1.0-alpha54-task-creation-trace` is unique versus recognition alpha42–53 and parallel alpha43.

## Authoritative alpha53 runtime evidence

Trace `conversation-identity-E076722C-E0F0-4044-8B99-41F727B1B62B.log`, enhancer `0.1.0-alpha53-refresh-path-trace`, app `1.2026.202`:

- Genuine A → B and B → A exact navigation emitted exact `conversation/init`, then exact `prepare` + conversation detail within about 125 ms.
- Genuine exact navigation snapshots showed `SwiftUI.UIKitNavigationController navCount=3`; same-A custom-route Sync/Reload produced one detail GET only, no exact init/prepare, no UI rebuild, and `navCount=1`.
- Alpha52 delivery-aware suppression worked: no second/third route burst after the first same-ID request delivery.
- All 11 alpha53 downstream `REFRESH-PATH` call-stack signatures were identical, so that logging point could not identify the upstream host navigation owner.

## Current candidate — alpha54 task-creation trace

- **Candidate**: `ENH-0.1.0-alpha54-task-creation-trace` / `0.1.0-alpha54-task-creation-trace`.
- **Source baseline**: alpha53 cleanup head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- **Build/test source**: `6d0f8537cde9d1f3029e4b0a5f39c9a0aa041142`.
- **Actions**: run `33042244321`, job `98418234062` — completed **success**. Checkout, run-id bookkeeping, Xcode check, Build, package upload and dylib upload all passed.
- **CI bookkeeping**: `fa5338712eea77194548e041472047e1dfe4b931`.
- **Post-CI cleanup/current branch head**: `aa00b1d164fd11e8f743e557b33eecd8dcb1bfd1`.
- **Post-CI compare**: build/test source → current head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha54-task-creation-trace`, id `9634299997`, Actions archive digest `sha256:560a89c13222875effba1e15e19d7afada4228ce0b111e2269fc2ecab3957834`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha54-task-creation-trace-dylib`, id `9634300301`, Actions archive digest `sha256:506f9db6c6df491a167b51fe0541bf5c7a6bec753efc5b949bdc6e159e494f2e`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, 594752 bytes, sha256 `cad6d1e1fdcc74b4c1cc25d2d3abed53f8af79b818d04e619073f01544224237`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha54 implementation

1. Production Sync/Reload behavior remains alpha52/53 unchanged; alpha54 is diagnostic-only.
2. Existing `NSURLSession` task-creation hooks now call `CEConversationIdentityTraceLogTaskCreation(...)` before the common observer path for non-enhancer/internal tasks.
3. The trace classifies only structural refresh-relevant stages: `exact-init`, `staging-init` (ID-less), `exact-prepare`, `staging-prepare` (ID-less), and exact conversation-detail GET.
4. New `REFRESH-CREATE` entries record the task-creation hook source, target ID when structurally present, key/root/top/presented controller classes, navigation-controller count/visible controller, bounded navigation-stack class composition, and a bounded sanitized caller stack captured closer to task creation.
5. Existing `REFRESH-PATH` also records stage and bounded navigation-stack composition, including ID-less init/prepare staging, for downstream correlation.
6. No Authorization, Cookie, account IDs, raw request templates, full headers, raw bodies or message contents are persisted. Upload-task bodies are used transiently only to extract the already-permitted structural conversation ID and are not written.
7. No production refresh/navigation mutation, manual init/prepare replay, forced nav-stack restoration, UIKit pop/push, History/sidebar navigation, alternate IDs, `/resume`, retry/watchdog/timer family, Catalog throttling, project-header work or percentage changes were added.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated request owner. Alpha54 diagnostics observe only.
- Server GET/request delivery is not visible Sync/Reload completion.
- Genuine init→prepare→detail and `navCount=3` are evidence of host state, not instructions to replay requests or mutate navigation stacks.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Install the exact alpha54 artifact and record one user-started trace: A visible → normal A → B → A → press `同步最新消息` once → wait for final status → export. Compare `REFRESH-CREATE` sources/caller signatures, navigation-stack composition, and ID-less staging between genuine navigation and the failed same-current route. Do not implement a production refresh mechanism unless this trace identifies an evidence-backed host entry path.