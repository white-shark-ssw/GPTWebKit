# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 当前会话识别，保证导出、拉取、重载只作用于真实当前会话。项目顶部标题替换继续降为次要问题；当前重点已经从“猜当前会话”转为利用 alpha46 真机证据确定可证明的精确会话 ID 来源。
- **Acceptance invariant**: **拉取、重载、导出必须使用真实当前 conversation ID，不得串会话；最终设计同时不能频繁误报“无法确认当前会话”。标题相同的两个会话必须也能精确区分。**
- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- **Working branch / PR / head rechecked after alpha46 runtime log**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; real head `96d845e7d750ea178ff73c12faed115dff33d14c`. Alpha46 build/test source `fc78d7d525969699fbd15a3f180e563e93e6d424`; CI bookkeeping `a99a9b99ec9c26e3537ee5a242f0cfa7c4764f88`; post-CI differences are bookkeeping/workflow cleanup only.
- **Current candidate**: `ENH-0.1.0-alpha46-conversation-identity-trace` / `0.1.0-alpha46-conversation-identity-trace`; Actions `32950198256`, job `98119660626`; package artifact id `9599824714`, dylib id `9599825427`.
- **Parallel preflight**: `DEV-conversation-usage` remains separate on `feat/conversation-usage`, candidate alpha43. No percentage-owned source was modified by alpha46. If later hiding all floating UI includes the percentage bubble, coordinate that separately.

## Authoritative prior runtime failures

- **alpha42 — rejected**: extended real-device use reproduced Pull Latest / Reload crossing to other conversations; project-header title replacement also ineffective.
- **alpha44 — rejected**: floating entry disappeared when identity was not yet proven.
- **alpha45 — not accepted**: current project chat could still fail closed with `无法确认当前可见会话，已取消重载。`; menu-scoped Rename could show the correct title but exact ID remained unproven.

## Alpha46 real-device trace — 2026-08-26

User completed the requested normal/project/repeated-switch/duplicate-title/force-close-relaunch trace and uploaded `conversation-identity-871F676C-DD34-40E3-B7FB-561BB0165581.log`.

### Trace coverage / quality

- 784 structured events across 2 process launch UUIDs over ~239 seconds.
- Recording survived force-close/relaunch as designed (`PROCESS-RESUME` continued the same trace session).
- 8 official `POST /backend-api/share/create` requests were captured across 6 unique conversations.
- Two different conversations both titled `测试会话` were exercised and produced different exact IDs.

### Confirmed finding A — Share is an exact action-scoped identity oracle

Every captured official Share-create request persisted an explicit request-body `conversation_id`:

- `优化会话识别v1` → `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7` (captured before and again after cold relaunch)
- `规则会话v1` → `6a8d85dc-7630-83ec-bf58-1f4e920135a8` (captured twice)
- `规划自定义客户端` → `6a8da245-c538-83ec-9303-da2952a46a1f`
- `会话百分比v1` → `6a8d9489-31e8-83ec-ad29-343a6b883e6d`
- first `测试会话` → `6a8ecf21-acf4-83ec-8616-fbe551b24df1`
- second `测试会话` → `6a8ecf4e-3740-83ec-a6a4-a532adecc011`

This is decisive duplicate-title evidence: the official Share flow knows the exact conversation ID independently of title. **However `/share/create` is side-effectful and must remain a validation oracle, not a hidden prerequisite for Pull/Reload/Export.** Do not create shared links silently just to discover identity.

### Confirmed finding B — explicit `conversation/init` is much stronger than generic network recency

The trace captured 10 `POST /backend-api/conversation/init` requests whose JSON body contained an explicit conversation ID, spanning 7 unique visible conversations. For every Share event that had a preceding explicit `conversation/init` in the recorded process (7/7 cases; the first Share started mid-page before any navigation was recorded), the most recent explicit init ID exactly matched the later Share body ID.

The exact init IDs also tracked repeated A↔B switching, project conversations and both duplicate-title conversations. No contradictory/background explicit-init ID was observed during this ~239s trace.

This is **strong runtime evidence** that `conversation/init` with an explicit body `conversation_id` is a foreground-navigation signal and is materially different from alpha42's unsafe rule “any observed conversation request wins”. It is not yet a universal guarantee across future app versions; final code should scope any authority specifically to this proven semantic endpoint/field, never generic request recency.

### Confirmed finding C — cold relaunch exposes the restored conversation ID immediately

On the second process launch, before user interaction:

1. `POST /backend-api/conversation/init` carried `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`.
2. `GET /backend-api/beacons/home?conversation_id=...` carried the same ID.
3. subsequent `/f/conversation/prepare` and `GET /backend-api/conversation/<same-id>` also matched.
4. later Share-create again carried the same ID.

So restoring the last conversation after a force-close has a concrete exact-ID path and does not require title guessing.

### Confirmed finding D — current top-right menu metadata itself did not expose the backend conversation ID

- Menu source-view scans reported `explicitConversationIDs=<none>`.
- Original Share/Pin/Archive/Delete action identifiers did not expose a UUID conversation ID in the logged public structural fields.
- The parent menu title was correct, including both duplicate `测试会话` instances, but title alone is not identity authority.
- 13 unique UUID-looking `UIContextMenuConfiguration` / menu configuration values were observed. **None intersected the 7 real conversation IDs seen in network evidence.** These are structural/configuration UUIDs, not backend conversation IDs.

### Confirmed finding E — generic UUID extraction is too broad

Current `CEExtractConversationIDFromString(...)` accepts any UUID-shaped string. Alpha46 trace formatting therefore labeled structural menu UUIDs as `conversationID=...` even though runtime comparison proves they are unrelated to real conversation IDs. `CECandidatesForSourceView(...)` also calls this generic extractor on an arbitrary `identifierText`, so treating arbitrary UIKit/menu UUIDs as conversation IDs is a dangerous latent path.

Future identity logic must accept IDs only from **semantically proven conversation locations/fields** (for example explicit JSON `conversation_id`, `/backend-api/conversation/<id>`, or another separately proven host field), not because a string merely looks like a UUID.

### Confirmed stale-global-context example

While the first duplicate-title `测试会话` was visibly active, menu trace still showed old context `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1`, but Share-create proved the real target was `6a8ecf21-acf4-83ec-8616-fbe551b24df1`. On the second duplicate-title chat, the old global context was still stale while Share proved `6a8ecf4e-3740-83ec-a6a4-a532adecc011`. This directly confirms why a long-lived title/UI-derived context cannot remain the sole proof used by actions.

## Current architecture direction after alpha46 evidence

The likely production design is now:

1. `CENetworkObserver` remains generic/passive for arbitrary requests, but a narrowly defined **explicit existing-conversation navigation-init signal** (`POST /backend-api/conversation/init` with explicit body `conversation_id`) may be promoted to foreground identity evidence because alpha46 directly validates it against Share, duplicate titles, project chats and cold relaunch.
2. Do not restore alpha42's “latest observed conversation request” rule; GET detail/background traffic remains non-authoritative by itself.
3. When the top-right conversation menu is built, capture an **immutable action target** from the currently proven exact ID rather than re-running title guessing when the user later taps Pull/Reload/Export.
4. Menu title may be used as a consistency check / presentation label, but never to choose between duplicate IDs.
5. Share-create remains a runtime validation oracle only; never silently create a public share link.
6. Remove arbitrary-UUID-as-conversation-ID behavior before relying on menu identifiers.
7. After exact menu action targeting is implemented and real-device accepted, move Pull/Reload/Export into the conversation menu and retire the current floating tool entry. Percentage floating UI remains a separate parallel-task decision.

## Validation state

- alpha46: **Code written → CI passed → Artifact produced → Runtime/manual/real-device trace tested successfully as instrumentation.**
- alpha46 does **not** claim Pull/Reload/Export fixed; it supplied the evidence needed for the next product candidate.
- Nothing is Stable/Frozen.

## Next exact action

**Do not modify alpha46.** Before product code, allocate a new unique recognition candidate, recheck PR/base/parallel conflicts, then make the smallest evidence-backed change that (a) rejects arbitrary structural UUIDs as conversation IDs, (b) derives foreground identity only from the proven explicit `conversation/init` body field rather than generic network recency, and (c) binds menu actions to an immutable exact ID captured at menu-build time. Keep Share as a diagnostic oracle and preserve fail-closed behavior if no proven exact ID exists. Then CI-build and real-device stress-test A↔B, duplicate titles, project chats, cold relaunch, Pull/Reload/Export.

## Rejected / do-not-repeat

- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/configuration identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- speculative timer/retry/watchdog/debounce;
- private Swift class hard-coding;
- claiming alpha46 instrumentation success means the cross-conversation bug is already fixed.