# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 当前会话识别，保证导出、拉取、重载只作用于真实当前会话。项目顶部标题替换继续降为次要问题；alpha46 已完成真机取证，alpha47 正在实现精确菜单目标。
- **Acceptance invariant**: **拉取、重载、导出必须使用真实当前 conversation ID，不得串会话；同名会话必须精确区分；正常已打开会话不得依赖标题猜测或频繁误报无法确认。**
- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked 2026-08-26 and unchanged.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; pre-alpha47 PR/head identity was `96d845e7d750ea178ff73c12faed115dff33d14c`, open/draft/mergeable. Current alpha47 code/package head is `ebd1455e7cef5133d25bc517a0c5e9ddfafc0410` before final workflow/CI synchronization.
- **Current candidate**: `ENH-0.1.0-alpha47-exact-menu-target` / product `0.1.0-alpha47-exact-menu-target`. Alpha43 remains reserved by parallel `DEV-conversation-usage`; alpha46 is the completed instrumentation candidate. No alpha47 CI/artifact yet.
- **Parallel preflight**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. User explicitly said “百分比不用管他了”; alpha47 has not modified percentage-owned files/checkpoint.

## Authoritative runtime evidence

### Prior failures

- **alpha42 — rejected**: Pull Latest / Reload crossed to other conversations; generic observed network traffic could overwrite foreground identity.
- **alpha44 — rejected**: floating conversation-tool button disappeared when identity was unproven.
- **alpha45 — not accepted**: project chat could false-negative `无法确认当前可见会话` even though menu-scoped Rename showed the right title.

### alpha46 trace — completed successfully as instrumentation

User uploaded `conversation-identity-871F676C-DD34-40E3-B7FB-561BB0165581.log`: 784 structured events across 2 app launches / ~239 seconds, including normal chats, project chats, repeated switching, duplicate-title chats, Share flows and force-close/relaunch.

- 8 official `POST /backend-api/share/create` requests across 6 unique conversations carried explicit body `conversation_id`.
- Two distinct chats both titled `测试会话` produced different exact IDs, proving title is not identity authority.
- For every Share event with a preceding explicit `POST /backend-api/conversation/init` body ID in the recorded process (7/7), the latest explicit init ID exactly matched Share.
- Explicit init tracked project chats, repeated A↔B, both duplicate-title chats and cold relaunch. No contradictory/background explicit-init ID appeared in this trace.
- Cold relaunch emitted restored-chat `conversation/init`, matching `beacons/home?conversation_id`, prepare/detail and later Share before UI guessing was needed.
- Top-right menu/source structural metadata did not expose the backend conversation ID.
- 13 UUID-looking menu/configuration IDs had zero intersection with 7 real conversation IDs. Arbitrary UUID syntax is not conversation identity evidence.
- Current global/UI-derived context was directly observed stale on both duplicate-title chats while Share proved the actual target.

## Alpha47 implementation — Code written at `ebd1455e...`

1. `CEConversationContext`: changing to a new exact ID with no known title clears the previous conversation title instead of carrying it across IDs.
2. `CEContextResolver`: retired the 1-second UIKit/title resolver and its constructor. Compatibility `CERefreshVisibleConversationContext()` now only returns the sole exact context owner; it no longer scans or writes identity.
3. `CENetworkObserver`: only exact `POST /backend-api/conversation/init` with exactly one explicit JSON `conversation_id` / `conversationId` value can update foreground `CEConversationContext`. Generic requests/resume traffic remain passive. Upload `fromData:` bodies are passed through the same semantic parser. Alpha46 trace logging remains available.
4. `CEEnhancerUI`: removed touch/title context mutation and left-edge context clearing. Arbitrary configuration UUIDs are no longer promoted to targets. Menu instrumentation no longer labels a bare structural UUID as a conversation ID.
5. Current-chat menu targeting: only a conversation menu tied to the current top-header touch/source region is augmented; this prevents a sidebar row menu from inheriting the open chat's ID. If a known host menu title conflicts with the catalog title of the exact context, augmentation is skipped rather than using the stale target.
6. Menu creation snapshots exact `conversationID` (+ title only for presentation/export naming). `拉取最新消息`, `重载当前会话`, `导出 Markdown` receive that immutable captured ID. On tap, the target must still equal the current exact context or the action is cancelled.
7. `CEManualConversationReload`: removed runtime method override/constructor and heuristic target lookup. It now exposes `CEManualReloadConversationID(exactID)` while preserving the established same-ID route delivery retries and official-request verification. It stops if context changes away from the captured target.
8. `CEFeatures`: added exact-ID Pull/Reload/Export entry points. Legacy current wrappers read only the exact context owner and no longer run visible-title proof.
9. Conversation-tool floating button/controller is removed from `CEEnhancerUI` startup/code. User explicitly approved this. Percentage UI from `DEV-conversation-usage` is untouched.
10. Project-header presentation code remains in place but is not part of alpha47 acceptance; it consumes exact context/catalog only and never feeds identity.
11. Candidate version/bootstrap/package identity is synchronized to `0.1.0-alpha47-exact-menu-target`; workflow artifact identity still needs final synchronization before CI.

## Static/source review so far

- Compare `96d845e... → ebd1455...` touches only recognition-owned Core/Network/UI/Features files plus `CEManualConversationReload.h` and `build.sh`; no percentage files changed.
- Current PR patch search shows old network/UI/title context writers removed; the only new foreground `setConversationID` writer is the explicit semantic `conversation/init` path.
- A function/static-variable name collision found during review in manual reload was corrected before CI (`CEManualReloadTargetID`).
- No local iOS SDK build evidence exists yet. Compile validation must come from final GitHub Actions run.

## Validation state

- alpha46: Code written → CI passed → Artifact produced → Runtime/manual instrumentation tested successfully.
- alpha47: **Code written. Static source review in progress. CI / Artifact / Runtime pending.**
- Nothing is Stable/Frozen.

## Required alpha47 real-device acceptance

1. Conversation-tool floating button is gone; percentage UI is outside this task and may remain.
2. Normal A → top-right current-chat menu → Pull/Reload/Export all target A.
3. A→B fast and slow switching → menu actions target B without stale A.
4. Two chats with identical titles → each current-chat menu action uses its own exact ID; no title chooser.
5. Project chat → menu actions use exact project-conversation ID.
6. Force-close/relaunch into last chat → after host init, menu actions target restored chat.
7. Keep identity trace available during stress acceptance; optional user-triggered official Share may be used as ground-truth comparison, never silently invoked.
8. Sidebar/other-row menu must not receive current-chat actions using the open chat's ID.

## Next exact action

Finish source review, synchronize `build-enhancer.yml` to alpha47 and temporarily add the feature branch trigger for one final candidate build. Immediately before CI recheck base + parallel heads and compare scope. Run one Actions build, record exact build/test source + bot bookkeeping + artifact IDs/digests, remove the temporary trigger without changing product source, update PR/docs, then hand the exact dylib to the user for real-device stress acceptance.

## Rejected / do-not-repeat

- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/configuration identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- speculative identity retry/watchdog/debounce;
- private Swift class hard-coding;
- injecting current-chat exact target into arbitrary sidebar row menus;
- touching percentage-owned files in this work.