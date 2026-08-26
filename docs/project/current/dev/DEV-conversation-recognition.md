# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别当前 ChatGPT iOS 会话，并确保 Pull / Reload / Export / Rename 只作用于真实当前 conversation；同时完善 Reload 完成语义和项目会话标题展示。
- **Acceptance invariant**: **Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。Reload 请求发生不等于 Reload 完成；插件生成标题只能用于 presentation，永远不能反向成为 identity evidence。**

## Resume identity / conflict guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- **Current product head**: `17f76c8428dad41484641b9dcf23a78935dbc32f`; alpha48 tested product source is `e2b133f0ba050b485e89129e4fe0ecb9bbee2343`; commits after tested source are CI run-id / temporary trigger cleanup only.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. User explicitly said percentage work is out of scope here; do not modify that task.
- **Base branch** remains unchanged from the verified baseline above.

## Current candidate — alpha48

- **Candidate**: `ENH-0.1.0-alpha48-reload-ui-title` / `0.1.0-alpha48-reload-ui-title`.
- **Actions**: run `32973529739`, job `98192604072` — success.
- **Artifacts**: package id `9608529953`, digest `sha256:256746f6fe6f7ea01e5a3e6d90f3a8bd47fa9f606366565fab8687ef18baf6a2`; dylib id `9608530563`, digest `sha256:a14dd7ae64931d45076459290fdd0674b3c9582c1b966e7fcb2d4b06814da840`.
- **Validation state**: **Code written → CI passed → Artifact produced → Runtime/manual partially tested and NOT accepted.** Nothing is Stable/Frozen.

## Identity architecture retained from alpha46/alpha47

- Alpha46 real-device trace proved explicit `POST /backend-api/conversation/init` request-body `conversation_id` tracks the foreground existing-chat target across normal/project chats, A↔B, duplicate titles and cold relaunch. Share-create body IDs independently matched 7/7 observed init targets.
- Arbitrary UUID-looking UIKit/menu/config identifiers are not conversation IDs.
- Only the validated explicit `conversation/init` body ID updates the sole long-lived `CEConversationContext`; generic/background traffic remains passive.
- Current top-right chat menu captures an immutable exact ID for current-conversation actions; action must cancel if exact context changes before tap.
- Old conversation-tool floating UI stays retired. Percentage UI is a separate task and untouched.
- Share remains validation-only and must never be silently invoked for identity discovery.

## Authoritative alpha48 runtime evidence

### 1. Exact target remained correct

User exported trace session `6CC3B3D6-2F4F-40A1-9D84-CABB7D0C7F3B` from alpha48 / ChatGPT app `1.2026.202`.

- Reload target stayed `6a8cbe3d-eaf8-83ec-92eb-68694f8baa0e`; no cross-conversation evidence appears in the trace.
- Route delivery produced same-ID `POST /backend-api/conversation/init` → `POST /backend-api/f/conversation/prepare` → `GET /backend-api/conversation/<id>`.

### 2. Reload UI proof false-negatived

- Trace starts Reload with `baselineUI=unproven`.
- All polls remained `uiRebuildObserved=NO` / `uiSawDisappear=NO`.
- User visually observed the page actually refresh.
- Therefore alpha48's current public-UIKit snapshot is not attached to the real ChatGPT message presentation tree on this host/runtime. Do not restore request-only success; replace only the incorrect UI evidence source after targeted view-tree evidence.

### 3. Page Reload did not prove interrupted generation recovery

- Original response had produced substantial reasoning/content, then client disconnected/timed out.
- After Reload the page visually refreshed, but the last turn remained stuck at `正在思考`.
- Trace was started after the original disconnect, so it does not contain the failure that killed the generation stream.
- During Reload the trace shows init/prepare/detail but no recorded `/backend-api/f/conversation/resume` or other explicit stream recovery request.
- This proves only re-entry/refetch of the conversation. It does **not** prove generation recovery, nor prove `/resume` is the missing correct action.
- Do not add speculative resume/retry/watchdog/status override until a trace starts before send and includes normal stream setup → disconnect/error → Reload → recovery/no-recovery.

### 4. Project header presentation still failed

- The current exact menu path repeatedly logged the correct title: `HEADER-TITLE ... title=轮播图优化v1`.
- UI still showed the project name and no gear marker.
- Therefore title acquisition is already correct; the remaining failure is presentation-target discovery/application.
- Current implementation scans `UILabel` objects under `CEKeyWindow()`. Runtime evidence does not yet prove whether failure is transient menu key-window selection, SwiftUI/non-UILabel rendering, or both. Capture the actual header view/window structure before changing the target mechanism. Do not add a periodic title timer.

### 5. Custom Rename option regression — confirmed

User reports the plugin's custom `重命名会话` option is missing in alpha48.

Source comparison confirms this is an enhancer regression introduced by the alpha47 exact-menu rewrite:

- alpha46 `CEAugmentedChildrenForSource(...)` explicitly injected `重命名会话` and called `CEFeatures renameCandidates:sourceView:`;
- alpha47/alpha48 current menu injection contains only `拉取最新消息` / `重载当前会话` / `导出 Markdown` / identity trace.

This is not a host-app menu disappearance.

**Restore rule for next candidate**:

- Restore `重命名会话` only in the proven current-header menu.
- Use the same immutable exact `capturedID` contract as Pull / Reload / Export.
- Before execution require `CEConversationContext.conversationID == capturedID`; otherwise cancel.
- Reuse existing rename UI/business code only after adapting its entry to an exact-ID record.
- **Do not restore alpha46 `CECandidatesForSourceView(...)` as execution authority**; it relied on source/title/identifier candidate heuristics intentionally removed from current-conversation authority.

## Current source facts relevant to Rename

- `CEFeatures.h` still exposes `renameCandidates:sourceView:`; the rename business path was not deleted from the feature module.
- The regression is the missing exact-menu action/entry, not evidence that rename backend/UI capability vanished.
- A future small API such as an exact-ID rename entry may be justified, but use existing naming/business functions and inspect the real rename implementation/call sites before coding; do not invent or rename interfaces for style.

## Next exact action

Do **not** allocate a new candidate solely from the Rename report. The next product candidate should bundle only evidence-backed fixes from this runtime batch:

1. restore exact-ID custom `重命名会话` in the current-header menu;
2. capture/fix the real project-header presentation target;
3. capture/fix the real message-view Reload evidence target;
4. generation recovery only after a trace begins before prompt send and proves the official stream/recovery lifecycle.

Before any product edit, recheck branch / PR / base / head / candidate allocations and the parallel alpha43 checkpoint. Preserve alpha47 exact identity ownership and do not touch percentage-owned code.

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