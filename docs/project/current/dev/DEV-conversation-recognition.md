# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别当前 ChatGPT iOS 会话，并确保 Pull / Reload / Export / Rename 只作用于真实当前 conversation；同时完善 Reload 完成语义和项目会话标题展示。
- **Acceptance invariant**: **Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。Reload 请求发生不等于 Reload 完成；插件生成标题只能用于 presentation，永远不能反向成为 identity evidence。**

## Resume identity / conflict guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked before and after alpha49 CI and unchanged.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR open/draft/mergeable.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned source/checkpoint untouched.
- **Candidate uniqueness**: alpha43 remains reserved by the parallel task; recognition alpha46/47/48 are historical allocations. alpha49 is unique.

## Current candidate — alpha49

- **Candidate**: `ENH-0.1.0-alpha49-exact-rename-ui-target` / product `0.1.0-alpha49-exact-rename-ui-target`.
- **Build/test source**: `3f3a04715e93755c1c04b4ca826aad2488c2a9a1`.
- **Actions**: run `32980682467`, job `98216287227` — completed **success**.
- **CI bookkeeping**: `0e1bb6a72bc41f05ff5addceeffa3164c413b817`.
- **Current branch head**: `9534ddb77bc43a979e34bd69b040d85ff38501dd`; compare from tested source changes only `.github/latest-enhancer-run-id` plus removal of the temporary feature-branch trigger. Product source is unchanged from the tested commit.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha49-exact-rename-ui-target`, id `9611305133`, digest `sha256:f3ec7f8c11e9acc268d6441f536ee54691a5be9d3e7247149dba7627341c6d30`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha49-exact-rename-ui-target-dylib`, id `9611306138`, digest `sha256:3d9bc9699a1a55aba5cd868f00f064707a63d014dca9a17c37e788607057c214`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing is Stable/Frozen.

## Alpha49 implementation

1. **Exact Rename restored**: current top-right chat menu again includes enhancer `重命名会话`. It captures the same immutable exact conversation ID as Pull/Reload/Export.
2. `CEFeatures renameConversationID:title:` creates the rename record from that exact ID; it does not use title/source-view/menu UUID candidate resolution to choose the target.
3. Rename checks `CEConversationContext.conversationID == capturedID` at menu-action entry and checks again immediately before the PATCH executes. If current context changed while the rename alert was open, operation cancels.
4. Successful rename updates the exact catalog record and attempts visible-title refresh across the foreground scene windows; no alternate conversation ID is used.
5. Added shared `CEForegroundWindows()` public-UIKit helper. It returns visible windows belonging to the foreground-active scene without changing conversation identity ownership.
6. **Project-header target**: `CEProjectConversationHeaderController` no longer searches only `CEKeyWindow()`. It searches foreground visible windows for the existing exact `聊天` header/title UILabel pair. If identity trace is active and no target is found, it records sanitized `HEADER-WINDOW` / `HEADER-LABEL` structural evidence for the next runtime diagnosis. No periodic title timer was added.
7. **Reload UI proof target**: `CEConversationUIReloadEvidence` now searches all visible foreground-scene windows for the dominant conversation-like `UIScrollView`, then captures anchors from the window that owns that scroll. This directly addresses alpha48 `baselineUI=unproven` when Reload was invoked from a context-menu surface.
8. Alpha48 completion contract remains unchanged: request-only is not success; same-ID official request **and** UI rebuild proof are still required.
9. Interrupted-generation recovery is intentionally unchanged. No `/resume`, speculative retry/watchdog/timer/status override was added because the previous trace began after the disconnect.
10. Version/bootstrap/build/workflow identities are synchronized to alpha49. Temporary recognition-branch CI trigger was removed after the successful build.

## Authoritative alpha48 runtime evidence motivating alpha49

- Trace `6CC3B3D6-2F4F-40A1-9D84-CABB7D0C7F3B` kept exact Reload target stable and showed same-ID `conversation/init → f/conversation/prepare → conversation detail`.
- User visually saw page refresh while alpha48 logged `baselineUI=unproven` and `uiRebuildObserved=NO`, proving the old key-window-based snapshot could miss the actual content surface.
- The trace repeatedly had the correct exact-ID menu title (`轮播图优化v1`) while the visible project header remained the project name/no gear, proving title acquisition was correct but presentation target/application was not.
- User confirmed enhancer custom Rename disappeared; source comparison showed alpha47's menu rewrite dropped the action while rename business code remained.
- The prior interrupted answer stayed at `正在思考` after page reload; current evidence is insufficient to prove the official generation recovery route.

## Identity architecture retained

- Only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity into the sole long-lived `CEConversationContext`.
- Generic/background request recency, arbitrary UUID-looking UI/config strings and title-only matching are not execution authority.
- Top-right current-chat menu freezes exact ID for Pull/Reload/Rename/Export and actions fail closed when current exact context changes.
- Share remains validation-only and is never silently invoked for discovery.
- Old conversation-tool floating UI stays retired. Percentage UI is a separate task and untouched.

## Required alpha49 real-device acceptance

1. Confirm enhancer `重命名会话` is back in the current top-right menu and renames the intended exact conversation.
2. Open rename, then if possible change/interrupt context before confirmation; it must cancel instead of touching another chat.
3. Verify Pull / Reload / Export still target only current exact chat.
4. In a project chat, open the current menu and confirm centered project name is replaced by the exact conversation title with the small gear marker. If still not, run identity trace so `HEADER-WINDOW` / `HEADER-LABEL` evidence reveals whether the host title is outside UIKit UILabel traversal.
5. Trigger Reload on a normal loaded conversation. A visually refreshed page should now produce a proven baseline/UI rebuild when the underlying conversation window was previously hidden behind the menu window. Request-only must still not report success.
6. Duplicate-title and A↔B stress remain safety checks.
7. Generation recovery is not an alpha49 acceptance claim; a future trace must start before prompt send/disconnect before that behavior changes.

## Rejected / do-not-repeat

- request observed == Reload completed;
- page/UI rebuilt == interrupted generation recovered;
- speculative resume/retry/watchdog without runtime evidence;
- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/config identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- private Swift class hard-coding;
- History/sidebar/UIKit navigation fallback or alternate conversation ID;
- enhancer-generated title as identity evidence;
- restoring alpha46 `CECandidatesForSourceView(...)` as current-conversation execution authority;
- touching percentage-owned files in this work.

## Next exact action

Hand the exact alpha49 artifact to the user and perform the real-device acceptance above. Record exact Rename/header/Reload results. Do not mark Stable/Frozen from CI/artifact evidence.