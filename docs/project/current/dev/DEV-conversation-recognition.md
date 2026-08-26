# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 当前会话识别与精确当前会话操作，保证导出、拉取、重载只作用于真实当前会话；当前追加两个同一精确身份链路上的需求：重载只有在真实页面刷新被证明后才能提示成功；项目会话顶部项目名应使用精确 ID 对应的真实会话标题替换，并以小齿轮图标标记为插件展示，且该标题绝不反向参与身份识别。
- **Acceptance invariant**: **拉取、重载、导出必须使用真实当前 conversation ID，不得串会话；同名会话必须精确区分；Reload 请求发生不等于 Reload 成功，只有页面/消息视图完成可证明的重新加载后才能显示成功；插件生成的标题只能是 presentation，永远不是 identity evidence。**

## Resume identity / conflict guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked immediately before alpha48 CI and unchanged.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; current branch head rechecked after alpha48 runtime report: `17f76c8428dad41484641b9dcf23a78935dbc32f`.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. User explicitly said “百分比不用管他了”; alpha48 did not modify percentage-owned files/checkpoint.
- **Alpha47 tested source**: `d297f65971fb6239cad2be7eb7fa9f8f8aab9f6d`; Actions `32969623709`, job `98180033708`; CI passed and artifacts produced. Bot bookkeeping `8c6e43bb4c4fde576152a7906075354d8817e5a0`; trigger cleanup `52ea5d9024054c72503af23d87249e8acda7b95c`.
- **Alpha47 runtime result**: current-chat menu UX is present, but user observed at least one Reload that reported success without an apparent page unload/reload. Source confirmed alpha47 returned success immediately when the same-ID official detail/resume request was observed. Therefore alpha47 proves request delivery, not complete Reload behavior, and is not accepted as complete Reload semantics.

## Current candidate — alpha48

- **Candidate**: `ENH-0.1.0-alpha48-reload-ui-title` / product `0.1.0-alpha48-reload-ui-title`.
- **Build/test source**: `e2b133f0ba050b485e89129e4fe0ecb9bbee2343`.
- **Actions**: run `32973529739`, job `98192604072` — completed **success**.
- **CI bookkeeping**: `7b2d9d9e709e431ec414b269bd72b4b33a092001`.
- **Current branch head**: `17f76c8428dad41484641b9dcf23a78935dbc32f`; compare from tested source changes only `.github/latest-enhancer-run-id` and removal of the temporary feature-branch CI trigger. Product source is unchanged from the tested commit.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha48-reload-ui-title`, id `9608529953`, digest `sha256:256746f6fe6f7ea01e5a3e6d90f3a8bd47fa9f606366565fab8687ef18baf6a2`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha48-reload-ui-title-dylib`, id `9608530563`, digest `sha256:a14dd7ae64931d45076459290fdd0674b3c9582c1b966e7fcb2d4b06814da840`.
- **Validation state**: **Code written → CI passed → Artifact produced → Runtime/manual partially tested and NOT accepted.** Nothing is Stable/Frozen.

## Authoritative alpha48 runtime evidence — 2026-08-26

User supplied a real-device screenshot from project chat `OnePlayer 播放器` and described the exact sequence:

1. A response had already emitted substantial visible reasoning/content, then the client disconnected/timed out.
2. User invoked plugin `重载当前会话`.
3. The conversation page visibly refreshed/reloaded, so alpha48's new UI-rebuild detector is plausibly observing a real page refresh in this case rather than request-only delivery.
4. After the refresh, the last turn remained indefinitely at `正在思考`; user judges that this turn is very likely never to produce an answer and appears stuck.
5. The project header still shows project name `OnePlayer 播放器`; requested conversation-title replacement + gear marker has **no visible effect**.

### Interpretation

- **Reload completion and generation recovery are separate states.** Alpha48 can now distinguish request delivery from page/UI rebuild, but a successful UI rebuild does not prove that an interrupted in-flight generation/stream has been resumed, reconciled, failed, or reached a terminal state. The screenshot exposes a new state gap: `page reloaded` while the host still renders a non-terminal `正在思考` placeholder that may have no live generation stream behind it.
- Do **not** add a speculative `/resume` call, retry loop, timer/watchdog, or status override yet. Current source only observes `/backend-api/f/conversation/resume`; it does not prove when/why the official client legitimately invokes it after a timeout, nor whether the stuck state is server-side `in_progress`, a missing stream reattachment, or stale client presentation.
- Existing alpha48 identity trace already records sanitized request paths, status/error, lifecycle, exact Reload action target, route-delivery, and UI-rebuild verification. The next evidence should first reproduce this interrupted-generation case with identity trace enabled before modifying recovery behavior.

### Header source finding

- `CEProjectConversationHeaderController.refresh:` currently calls `CEKeyWindow()` and searches only that one window for the exact `聊天` subtitle/title pair.
- The exact conversation title is updated during current-header context-menu construction. At that moment iOS may make the context-menu/presentation window the key window; that overlay window does not contain the underlying project header. `refresh:` then sees no target and there is no later retry when the menu closes.
- This is a source-supported explanation for “菜单里已经有正确会话标题，但项目顶部仍保持项目名”. A future minimal header fix should search foreground scene windows for the real project-header label instead of assuming the current key window is the host content window. It must not add a periodic title timer and must preserve synthetic-title exclusion.

## Identity architecture retained from alpha46/alpha47

- Alpha46 trace proved explicit `POST /backend-api/conversation/init` body `conversation_id` tracks foreground existing-chat navigation across normal/project chats, A↔B, duplicate titles and cold relaunch; Share-create body IDs independently matched 7/7 observed init targets.
- Arbitrary UUID-looking menu/configuration identifiers are not conversation IDs.
- Only the explicit semantic `conversation/init` body ID updates the sole long-lived `CEConversationContext`; generic/background conversation traffic remains passive.
- Top-right current-chat menu captures an immutable exact ID for Pull/Reload/Export; actions cancel if current exact context changes.
- The old conversation-tool floating button remains retired. Percentage UI is outside this task and untouched.
- Share remains a validation oracle only and is never silently invoked for identity discovery.

## Alpha48 implementation

1. **Reload request ≠ reload completion**: `CEManualConversationReload.mm` still uses the existing exact-ID custom-route attempts and same-ID safety, but an official detail/resume request no longer immediately produces `✓ 当前会话已重载`.
2. Added `UI/CEConversationUIReloadEvidence.mm`, using only public UIKit. At reload start it captures an ephemeral snapshot of the dominant visible conversation-like `UIScrollView` plus visible text/accessibility anchor object identities. During the existing reload poll lifecycle it compares the current snapshot with the baseline.
3. **Reload success now requires both proofs**: (a) same exact conversation official reload/detail request observed after route delivery; and (b) current conversation UI shows a rebuild/refresh signal — conversation scroll object replacement, substantial visible anchor identity turnover, or visible conversation content disappearing and then returning.
4. No independent timer/watchdog/retry family was added. Evidence sampling reuses the existing reload poll lifecycle and existing same-ID route attempts only.
5. If request delivery is proven but UI rebuild is not, final message is `已触发当前会话请求，但未确认页面完成刷新。`; it must not claim success.
6. `CEEnhancerUI` treats the already-visible official current-chat menu title as **presentation metadata for the already-proven exact target ID only**. It may update that exact record's title, but it never chooses or changes identity.
7. Updating the exact record title posts the existing catalog notification while the project header is present. The existing `CEProjectConversationHeaderController` then attempts to replace the project-name header with that conversation title.
8. The rewritten title retains the synthetic marker exclusion contract and gets a small `gearshape.fill` `UIImageView` on its left when successfully applied.
9. The plugin-rewritten header is never consumed by current-conversation identity paths, preserving TD-005.
10. Version/bootstrap/package/workflow artifact identity is synchronized to alpha48.

## Next exact action

**Do not change generation recovery code yet.** Ask the user to use alpha48's existing `开始会话识别记录`, then reproduce one interrupted/timeout generation followed by `重载当前会话`, wait long enough to establish whether `正在思考` remains stuck, and export the trace. Inspect the exact request/response/error sequence around Reload, especially conversation detail, prepare/resume and any stream/network completion errors. From that evidence decide whether the true owner is server message status, stream reattachment, or stale client UI. In parallel, the project-header key-window limitation is already source-supported and can be fixed minimally in the next candidate without changing identity authority.

## Rejected / do-not-repeat

- request observed == reload completed;
- page/UI rebuilt == interrupted generation recovered;
- speculative resume/retry/watchdog without runtime evidence;
- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/configuration identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- private Swift class hard-coding;
- History/sidebar/UIKit navigation fallback or alternate conversation ID;
- enhancer-generated title as identity evidence;
- touching percentage-owned files in this work.