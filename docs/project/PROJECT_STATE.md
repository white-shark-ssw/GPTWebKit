# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha53-refresh-path-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `b62878928816c40cbed8c11847a3ed7ae494adde`; CI bookkeeping `fa926ca61013292056e647f78d1d1677b608a72b`; post-CI cleanup head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- CI passed: Actions `33007145536`, job `98303728684`.
- Artifacts: package id `9621009139`, digest `sha256:500a38652acf60b50f15f5ace41ca31e68a198cda3acaf724f1547f88bbeb6b2`; dylib id `9621009533`, Actions archive digest `sha256:5648a23263eb0d7fa535387a5f7fcbe2d8622142f0bdfd862515be32bb7d59a8`.
- Extracted dylib: arm64 Mach-O, 594000 bytes, sha256 `78a38421fe04adba9774bb8e42947ea48120d2a61698359f04c31bdb6f6f86a2`.
- Status: **Code written → CI passed → Artifact produced → Runtime/manual/real-device partially tested.**

## Alpha53 runtime evidence — 2026-08-27

Trace `conversation-identity-E076722C-E0F0-4044-8B99-41F727B1B62B.log`, app `1.2026.202`:

- Normal A → B exact navigation targeted `6a8daab4-49ac-83ec-9983-f4c96805c6ca`; exact init was followed by exact prepare/detail traffic within ~123 ms. Normal B → A exact navigation targeted `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`; exact prepare/detail followed within ~125 ms.
- Every exact genuine-navigation `REFRESH-PATH` snapshot reported `SwiftUI.UIKitNavigationController` with `navCount=3`.
- After returning to A, one `同步最新消息` used the same exact A ID. The handoff entered Reload about 9.25 s later; route attempt 0 opened once and produced one same-ID detail GET about 1.73 s later, with no exact init/prepare and no UI rebuild.
- Alpha52 delivery-aware suppression worked: no second/third custom route was sent after same-ID request delivery was proven. Final status was `已请求客户端刷新，但页面未发生刷新。`.
- The failed same-current detail GET reported the same top-controller class as genuine detail/prepare but `navCount=1`, not 3. This is a structural difference between genuine navigation and the custom URL route, but it does not establish a safe production navigation mutation.
- All 11 captured `REFRESH-PATH` call-stack signatures were identical across genuine init/prepare/detail and failed same-current detail. The current call-stack capture point is therefore too downstream/common to identify the upstream host navigation owner.
- UI baseline remained `unproven`; verifier samples remained `uiRebuildObserved=NO` / `uiSawDisappear=NO`, consistent with the failed visible refresh.
- No HTTP 429 occurred; terminal 429 behavior remains runtime-unexercised in trace evidence.

## Current conclusions

- Exact-current identity remains correct in the alpha53 capture.
- Genuine navigation continues to show init → prepare → detail traffic and a navigation-stack count of 3; same-current custom-route refresh remains detail-only and showed a stack count of 1.
- Network traffic remains evidence of host navigation state, not a replay recipe.
- Do not manually replay init/prepare, force navigation-stack restoration, add UIKit pop/push, alternate IDs, `/resume`, watchdogs or extra route variants from this evidence.
- Alpha53 diagnostic call-stack sampling did **not** reveal a production refresh entry point. A narrower diagnostic must capture closer to actual task creation and include bounded navigation-stack composition / ID-less init/prepare staging before a production refresh change is justified.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated explicit `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current request rather than a burst-retry trigger.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof, never identity authority.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority.

## Other retained runtime findings

- Alpha50 project-header trace proved exact identity/title acquisition but rejected the current UIKit `聊天 UILabel + nearby title UILabel` target on app `1.2026.202`; user has paused this feature.
- Reload request delivery is not Reload completion, and UI rebuild is not proof that an interrupted generation stream recovered.
- Sidebar Rename/Export selected-row acceptance and duplicate-title behavior remain pending real-device verification.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha53 did not modify percentage-owned source/checkpoint.

## Next evidence

- Before implementing a new host refresh mechanism, refine diagnostics only: capture first observation source at NSURLSession task creation, bounded public navigation-controller stack class composition, and ID-less init/prepare structural staging.
- Then run one A → B → A → `同步最新消息` trace and compare the genuine navigation path with the same-current route.
- This diagnostic work does not authorize History/sidebar navigation, UIKit stack restoration or manual init/prepare replay as production behavior.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.