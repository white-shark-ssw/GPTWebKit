# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 当前会话识别，保证导出、拉取、重载只作用于真实当前会话。项目顶部标题替换继续降为次要问题；alpha46 已完成真机取证，当前进入精确菜单目标的正式产品实现。
- **Acceptance invariant**: **拉取、重载、导出必须使用真实当前 conversation ID，不得串会话；同名会话必须精确区分；正常已打开会话不得依赖标题猜测或频繁误报无法确认。**
- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked 2026-08-26 and unchanged.
- **Working branch / PR / pre-alpha47 head**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; branch/PR head `96d845e7d750ea178ff73c12faed115dff33d14c`; PR open/draft/mergeable. Alpha46 build/test source `fc78d7d525969699fbd15a3f180e563e93e6d424`; CI bookkeeping `a99a9b99ec9c26e3537ee5a242f0cfa7c4764f88`; post-CI differences are bookkeeping/workflow cleanup only.
- **New candidate allocated — 2026-08-26**: `ENH-0.1.0-alpha47-exact-menu-target` / product `0.1.0-alpha47-exact-menu-target`. Alpha43 remains reserved by parallel `DEV-conversation-usage`; alpha46 remains the completed instrumentation candidate. No alpha47 artifact exists yet.
- **Parallel preflight**: only other Active task is `DEV-conversation-usage` on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Its percentage-owned files remain separate. User explicitly said “百分比不用管他了”; alpha47 must not modify percentage files/checkpoint. Current branch may retire only `CEEnhancerUI`'s conversation-tool floating button.

## Authoritative runtime evidence

### Prior failures

- **alpha42 — rejected**: Pull Latest / Reload crossed to other conversations; generic observed network traffic could overwrite foreground identity.
- **alpha44 — rejected**: floating conversation-tool button disappeared when identity was unproven.
- **alpha45 — not accepted**: project chat could false-negative `无法确认当前可见会话` even though menu-scoped Rename showed the right title.

### alpha46 trace — completed successfully as instrumentation

User uploaded `conversation-identity-871F676C-DD34-40E3-B7FB-561BB0165581.log`: 784 structured events across 2 app launches / ~239 seconds, including normal chats, project chats, repeated switching, duplicate-title chats, Share flows and force-close/relaunch.

- 8 official `POST /backend-api/share/create` requests across 6 unique conversations carried explicit body `conversation_id`.
- Two distinct chats both titled `测试会话` produced different exact IDs, proving title is not needed for exact identity.
- For every Share event with a preceding explicit `POST /backend-api/conversation/init` body ID in the recorded process (7/7), the latest explicit init ID exactly matched Share.
- Explicit init tracked project chats, repeated A↔B, both duplicate-title chats and cold relaunch. No contradictory/background explicit-init ID appeared in this trace.
- Cold relaunch emitted restored-chat `conversation/init`, matching `beacons/home?conversation_id`, prepare/detail, then later matching Share before any identity guess was needed.
- Top-right menu/source structural metadata did not expose the backend conversation ID.
- 13 UUID-looking menu/configuration IDs had zero intersection with 7 real conversation IDs. Arbitrary UUID syntax is therefore not conversation identity evidence.
- Current global/UI-derived context was directly observed stale on both duplicate-title chats while Share proved the actual target.

## Alpha47 implementation contract

1. Promote **only** the proven semantic signal `POST /backend-api/conversation/init` with an explicit JSON `conversation_id` / `conversationId` field to foreground identity evidence. Generic request recency remains passive.
2. `CEConversationContext` remains the sole long-lived state owner. When identity changes without a known title, do not carry the previous conversation's title across the ID change.
3. Retire UI/title-derived context writers: no periodic title/visible-string resolver and no touch/title candidate may overwrite exact init identity.
4. Menu build captures an immutable exact conversation ID from the current `CEConversationContext`; actions use that captured target directly and do not re-run title matching/visible proof when tapped.
5. Pull Latest, Reload and Export Markdown become enhancer actions in the conversation menu. Export receives a record built from the captured exact ID; title is presentation only.
6. Remove arbitrary menu/configuration UUID promotion: `UIContextMenuConfiguration.identifier` and other structural UUIDs cannot create a conversation target.
7. Official Share-create remains a diagnostic/acceptance oracle only; never invoke it silently.
8. User explicitly approved retiring the current conversation-tool floating button. Do not touch the percentage floating UI owned by `DEV-conversation-usage`.
9. Keep alpha46 sanitized trace available for alpha47 validation; do not add new timers/retries/watchdogs/fallback identity caches.

## Validation state

- alpha46: Code written → CI passed → Artifact produced → Runtime/manual instrumentation tested successfully.
- alpha47: **Candidate allocated; product code not yet written; no CI/artifact/runtime evidence yet.**
- Nothing is Stable/Frozen.

## Required alpha47 real-device acceptance

1. Normal A → menu Pull/Reload/Export all target A.
2. A→B fast and slow switching → menu actions target B without stale A.
3. Two chats with identical titles → each menu action uses its own exact ID; no chooser based on title.
4. Project chat → menu actions use exact project-conversation ID.
5. Force-close/relaunch into last chat → after host init, menu actions target restored chat.
6. Keep alpha46 trace running during stress acceptance and compare action target IDs against optional user-triggered official Share ground truth.
7. No current conversation-tool floating button. Percentage UI is outside this task and unchanged.

## Next exact action

Implement the smallest alpha47 source change across `CEConversationContext`, `CENetworkObserver`, `CEContextResolver`, `CEEnhancerUI`, `CEFeatures` and manual reload entry so exact init identity is the only foreground writer and menu actions carry immutable exact targets. Then synchronize version/package/workflow identity, recheck base/parallel heads, run one final CI candidate build, record artifact identity, and hand the dylib to the user.

## Rejected / do-not-repeat

- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/configuration identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- speculative retry/watchdog/debounce for identity;
- private Swift class hard-coding;
- touching percentage-owned files in this work.