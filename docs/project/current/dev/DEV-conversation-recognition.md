# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 当前会话识别与精确当前会话操作，保证导出、拉取、重载只作用于真实当前会话；当前追加两个同一精确身份链路上的需求：重载只有在真实页面刷新被证明后才能提示成功；项目会话顶部项目名应使用精确 ID 对应的真实会话标题替换，并以小齿轮/扳手图标标记为插件展示，且该标题绝不反向参与身份识别。
- **Acceptance invariant**: **拉取、重载、导出必须使用真实当前 conversation ID，不得串会话；同名会话必须精确区分；Reload 请求发生不等于 Reload 成功，只有页面/消息视图完成可证明的重新加载后才能显示成功；插件生成的标题只能是 presentation，永远不是 identity evidence。**

## Resume identity guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked and unchanged.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR is open/draft/mergeable.
- **Alpha47 tested source**: `d297f65971fb6239cad2be7eb7fa9f8f8aab9f6d`; Actions bookkeeping head `8c6e43bb4c4fde576152a7906075354d8817e5a0`; post-build trigger cleanup `52ea5d9024054c72503af23d87249e8acda7b95c` changes workflow only.
- **Alpha47 candidate**: `ENH-0.1.0-alpha47-exact-menu-target` / `0.1.0-alpha47-exact-menu-target`; Actions `32969623709`, job `98180033708`; package artifact id `9607073111`, digest `sha256:c5c4f8aeafecd67b5babbfe8130253bb8d56e9e178df7e50e771d7e2676ffbc2`; dylib artifact id `9607074065`, digest `sha256:2c8815d8beeefa703ac7a139d55b243d905eb5fd51b14ff3d1964f5d6decf5cb`.
- **Alpha47 runtime evidence**: user confirms the menu UX is present and reports at least one Reload showing success while the page did not visibly appear to unload/reload. This means current Reload success semantics are insufficient: observing a same-ID official detail/resume request proves request delivery only, not actual current-page reload completion. Alpha47 is therefore not accepted as complete Reload behavior.
- **Parallel preflight**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. User explicitly said “百分比不用管他了”; this task must continue to leave percentage-owned files/checkpoint untouched.
- **New candidate allocated**: `ENH-0.1.0-alpha48-reload-ui-title` / product `0.1.0-alpha48-reload-ui-title`. Alpha48 is unique in current BUILD_TEST_INDEX and does not reuse alpha43/alpha47 identities.

## Authoritative identity evidence retained

- Alpha46 trace proved explicit `POST /backend-api/conversation/init` body `conversation_id` tracks foreground existing-chat navigation across normal/project chats, A↔B, duplicate titles and cold relaunch; Share-create body IDs independently matched 7/7 observed init targets.
- Arbitrary UUID-looking menu/configuration identifiers are not conversation IDs.
- Alpha47 moved current-chat Pull/Reload/Export into the top-right current conversation menu, captures immutable exact IDs, removed the old conversation-tool floating button, and left percentage UI untouched.
- Generic/background conversation traffic, title-only matching, UIKit/menu UUIDs and Share side effects remain prohibited identity sources.

## Alpha48 scope / design constraints

1. **Reload completion semantics**: preserve exact-ID custom-route delivery and same-ID safety. The existing official request observation remains the first proof that reload delivery occurred, but it must no longer directly produce `✓ 当前会话已重载`.
2. Add the smallest public-UIKit evidence needed to distinguish “request happened” from “current message UI actually refreshed/rebuilt”. Reuse the existing reload attempt/poll lifecycle; do not add an independent watchdog/timer/state authority.
3. A successful Reload requires both: (a) same exact conversation official reload/detail request after route delivery; and (b) current conversation content UI shows a post-route refresh/rebuild event attributable to that reload. If only (a) occurs, do not claim success; continue only the existing same-ID route attempts, then report that the request was sent but page refresh was not confirmed.
4. **Project header title**: derive the display title from the exact current conversation ID via `CECatalog`/fetched conversation data. Replace the project-name header only for the project-chat header shape already recognized by current code, and add a small `gearshape.fill` or wrench-style `UIImageView` immediately left of the rewritten title.
5. The rewritten header must remain marked synthetic and excluded from identity evidence per TD-005. It may never write or reinforce `CEConversationContext`.
6. Do not touch percentage-owned source/UI.
7. Do not add History/sidebar/UIKit navigation fallback, alternate IDs, generic request recency authority, title-based execution target, new periodic timer, retry family, or second conversation authority.

## Validation state

- alpha46: Code written → CI passed → Artifact produced → Runtime/manual instrumentation tested successfully.
- alpha47: Code written → CI passed → Artifact produced → Runtime/manual partially tested; exact menu targeting still needs broader stress acceptance, and Reload completion semantics are **not accepted** because request observation can produce a success message without proven UI reload.
- alpha48: **Candidate allocated; code not yet written.**
- Nothing is Stable/Frozen.

## Required alpha48 real-device acceptance

1. Normal/project/same-title chats retain exact menu targeting from alpha47; no cross-conversation action.
2. Reload success message appears only when exact same-ID reload request **and** current message UI refresh/rebuild are both observed.
3. If request occurs without provable UI refresh, it must not say success; final message must distinguish “请求已触发但未确认页面刷新”.
4. Actual successful reload should show real message-view refresh/reconstruction; visible blanking is not mandatory if the host keeps old UI for continuity.
5. Project chat header replaces project name with the exact conversation's real title and shows a small plugin marker icon on its left.
6. Switching to another project conversation updates the rewritten title from exact ID; duplicate titles do not affect identity.
7. Plugin-rewritten title never changes identity and never becomes evidence for Pull/Reload/Export.
8. Percentage feature remains untouched.

## Next exact action

Inspect the current alpha47 reload/UI implementation and current public UIKit hierarchy evidence hooks, implement the minimum alpha48 reload-completion proof plus exact-ID project header presentation, synchronize version/package/workflow identity, recheck base + parallel heads immediately before final CI, run one isolated alpha48 Actions build, record artifact identity, remove the temporary branch trigger without changing product source, update PR/docs, and hand the exact dylib to the user for real-device acceptance.

## Rejected / do-not-repeat

- request observed == reload completed;
- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/configuration identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- speculative extra reload retry/watchdog/debounce;
- private Swift class hard-coding;
- History/sidebar/UIKit navigation fallback or alternate conversation ID;
- enhancer-generated title as identity evidence;
- touching percentage-owned files in this work.