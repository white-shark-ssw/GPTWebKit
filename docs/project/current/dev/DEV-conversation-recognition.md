# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` = `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged before alpha53 runtime analysis.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; real branch head rechecked at `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`; PR remains open/draft/mergeable at the same head.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not touch percentage-owned files/checkpoint.
- **Candidate uniqueness**: recognition alpha42–53 and parallel alpha43 are allocated; alpha53 remains the current diagnostic candidate.
- **No Frozen conflict**: product modules remain Active. Alpha53 is diagnostic-only and does not change identity ownership or production refresh semantics.

## Previous candidate — alpha52

- **Candidate**: `ENH-0.1.0-alpha52-sync-refresh-handoff` / `0.1.0-alpha52-sync-refresh-handoff`.
- **Build/test source**: `9c06219cdee1ac00b75372f1480278169b3f6e59`.
- **Actions**: run `33004675627`, job `98295074960` — success.
- **Post-CI cleanup head**: `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- **Artifacts**: package id `9620028731`; dylib id `9620029383`; extracted dylib sha256 `0b19bb2ec6d2b9a5ff26210bbd8d8945cffa77bb280b38e28ef1e0f9dc7f62d5`.
- **Validation**: Code written → CI passed → Artifact produced → Runtime/manual partially tested. Nothing Stable/Frozen.

## Authoritative alpha52 A → B → A runtime evidence — 2026-08-27

Trace `conversation-identity-585B0B11-C85D-4A19-BA16-4F55D56A320A.log`, enhancer `0.1.0-alpha52-sync-refresh-handoff`, app `1.2026.202`:

- Normal exact navigation emitted target `conversation/init`, then within ~125 ms exact `prepare` + conversation detail GET (+ another prepare).
- Alpha51 failed same-current custom-route Reload emitted only same-ID detail GETs and zero exact init/prepare while the page did not rebuild.
- Therefore genuine host navigation/rebuild correlates with a host navigation-state transition that produces init → prepare → detail traffic; these network calls are consequences/evidence, not a replay recipe.

## Current candidate — alpha53 refresh-path trace

- **Candidate**: `ENH-0.1.0-alpha53-refresh-path-trace` / `0.1.0-alpha53-refresh-path-trace`.
- **Source baseline**: alpha52 post-CI head `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- **Build/test source**: `b62878928816c40cbed8c11847a3ed7ae494adde`.
- **Actions**: run `33007145536`, job `98303728684` — completed **success**.
- **CI bookkeeping**: `fa926ca61013292056e647f78d1d1677b608a72b`.
- **Post-CI cleanup/current branch head**: `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- **Post-CI compare**: tested source → current head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha53-refresh-path-trace`, id `9621009139`, digest `sha256:500a38652acf60b50f15f5ace41ca31e68a198cda3acaf724f1547f88bbeb6b2`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha53-refresh-path-trace-dylib`, id `9621009533`, Actions archive digest `sha256:5648a23263eb0d7fa535387a5f7fcbe2d8622142f0bdfd862515be32bb7d59a8`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, 594000 bytes, sha256 `78a38421fe04adba9774bb8e42947ea48120d2a61698359f04c31bdb6f6f86a2`.
- **Validation state**: **Code written → CI passed → Artifact produced → Runtime/manual/real-device partially tested.** Nothing Stable/Frozen.

## Authoritative alpha53 combined runtime evidence — 2026-08-27

Trace `conversation-identity-E076722C-E0F0-4044-8B99-41F727B1B62B.log`, enhancer `0.1.0-alpha53-refresh-path-trace`, app `1.2026.202`, one launch / 180 structured events:

- Trace begins on A `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`.
- Normal A → B exact target was `6a8daab4-49ac-83ec-9983-f4c96805c6ca`. Exact B init at `1787774659027` was followed by exact prepares at +117 ms/+121 ms and exact detail GET at +123 ms. All exact B `REFRESH-PATH` snapshots reported `SwiftUI.UIKitNavigationController` with `navCount=3`.
- Normal B → A exact init at `1787774677483` was followed by exact A prepare at +121 ms, detail GET at +124 ms and second prepare at +125 ms. All exact A genuine-navigation snapshots also reported the same navigation controller with `navCount=3`.
- Identity remained exact: `IDENTITY-INIT` accepted B, then A.
- After returning to A, `ACTION-SYNC` used the same exact A ID. Sync entered Reload about 9.25 s later. Route attempt 0 opened once and, ~1.73 s later, produced only one same-ID detail GET. No exact init or exact prepare appeared during the Sync/Reload handoff.
- Alpha52 delivery-aware suppression worked: after the one delivered detail GET and no UI rebuild, alpha53 emitted `stop-repeat-route` and finished with `已请求客户端刷新，但页面未发生刷新。`; no second/third route burst occurred.
- The failed same-current detail GET had the same `topVC` class as genuine detail/prepare snapshots but `navCount=1`, while genuine exact navigation snapshots had `navCount=3`. This is a new structural difference and suggests the custom URL route reaches a different/incomplete public navigation-container state; it does **not** prove a safe way to mutate that state.
- All 11 `REFRESH-PATH` call-stack signatures were identical, including genuine init/prepare/detail and failed same-current detail. Therefore the alpha53 call-stack capture point is too downstream/common to identify the host navigation caller; the current stack signature is **not** production-entry evidence.
- Reload UI baseline remained `unproven` and all verifier samples remained `uiRebuildObserved=NO` / `uiSawDisappear=NO`, matching the failed visible-refresh result.
- No HTTP 429 occurred; terminal 429 behavior remains separately unexercised in trace evidence.

## Alpha53 conclusions

1. Exact identity and alpha52 one-delivery suppression are behaving as designed in this capture.
2. Genuine navigation remains clearly different from custom-route refresh: init + prepare + detail and `navCount=3` versus detail-only and `navCount=1`.
3. The current `NSThread.callStackSymbols` collected from `CEConversationIdentityTraceLogRequest` is not useful for identifying the upstream navigation owner because every semantic request produced the same stack.
4. Do not implement manual init/prepare replay, force navigation-stack restoration, UIKit pop/push, alternate IDs, `/resume`, watchdogs or extra route variants from this evidence.
5. A next diagnostic, if continued, should move structural capture closer to the actual NSURLSession task-creation hook and/or record bounded navigation-controller stack composition and ID-less init/prepare staging. This is diagnostic evidence collection only; no production refresh mechanism is yet proven.

## Architecture retained / rejected routes

- Sole active identity owner: `CEConversationContext`; only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity.
- Generic request recency, title-only matching and arbitrary UUIDs are not identity authority.
- Current menu freezes exact ID; sidebar Rename/Export remain row-scoped.
- `CEAPIClient` remains sole enhancer-originated request owner; 429 remains terminal for the current request.
- Do not claim GET/request/openURL success as UI Sync/Reload success.
- Do not automatically repeat same-route delivery once exact same-ID request delivery is proven but UI effect is absent.
- Genuine navigation traffic is evidence of host state transition, not authorization to replay its requests manually.
- Project-header work remains paused; percentage-owned files remain untouched.

## Next exact action

Use the alpha53 result as the baseline. Before any production refresh implementation, add only a narrower diagnostic capture that can distinguish the upstream creation/navigation path: record the first observation source at NSURLSession task creation, bounded public navigation-stack class composition, and structural snapshots for the ID-less init/prepare staging that precedes exact genuine navigation. Then run one more A → B → A → Sync trace. Do not change production Sync/Reload behavior until that evidence identifies a real host entry path.