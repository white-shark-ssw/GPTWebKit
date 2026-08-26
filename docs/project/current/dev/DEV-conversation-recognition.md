# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Pull / Reload / Export / Rename 不串会话；同时保留侧栏会话行的安全 Rename / Export、完善 Reload 完成语义和项目会话标题展示。
- **Acceptance invariant**: **当前会话 Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏长按 Rename / Export 必须作用于被长按的会话行，不得借用当前页面 ID；若只能得到同名候选，必须显式选择或失败关闭，禁止猜测。Reload 请求发生不等于 Reload 完成；插件生成标题只能用于 presentation，永远不能反向成为 identity evidence。**

## Resume identity / conflict guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged before alpha50 work.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; branch/PR head rechecked at `9534ddb77bc43a979e34bd69b040d85ff38501dd`, PR open/draft/mergeable.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned source/checkpoint remains out of scope.
- **Candidate uniqueness check**: alpha43 is reserved by the parallel task; recognition alpha46/47/48/49 are already allocated. `ENH-0.1.0-alpha50-sidebar-menu-actions` is newly allocated and unique.

## Authoritative alpha49 runtime evidence — 2026-08-26

- User confirms the custom options shown from the **current conversation top-right `...` menu are now correct** in alpha49.
- User reports a regression/coverage gap: **long-pressing a conversation in the conversation list no longer shows enhancer custom options** and requests restoring only `重命名会话` and `导出 Markdown` there.
- Current alpha49 source explains this directly: `CEAugmentedChildrenForSource(...)` returns the original menu whenever `CEIsCurrentConversationHeaderSource(...)` is false. That protection was correct for preventing Pull/Reload/current-ID actions from leaking into sidebar menus, but it also removed the older sidebar Rename/Export UX.
- This runtime result does not yet prove alpha49 project-header title or Reload UI proof behavior; leave those acceptance items pending.

## Current candidate — alpha50

- **Candidate**: `ENH-0.1.0-alpha50-sidebar-menu-actions` / product `0.1.0-alpha50-sidebar-menu-actions`.
- **Source baseline**: alpha49 post-CI head `9534ddb77bc43a979e34bd69b040d85ff38501dd`.
- **Planned minimal change**:
  1. keep the current top-right menu path exactly on alpha49 immutable current-ID semantics;
  2. for conversation-like menus that are **not** the current top header, inject only `重命名会话` and `导出 Markdown`;
  3. sidebar/non-current target resolution must never use `CEConversationContext` and must never parse an arbitrary menu/config UUID as conversation identity;
  4. resolve only from the row/menu-scoped visible/accessibility conversation title against `CECatalog`; a unique title yields one exact catalog record, duplicate titles yield the full candidate set and existing `CEFeatures renameCandidates:` / `exportCandidates:` requires explicit user selection; no match fails closed;
  5. do not add Pull/Reload/identity-trace actions to sidebar menus;
  6. do not mutate active conversation context from a sidebar long press;
  7. do not change percentage, generation recovery, Reload semantics or project-title logic in this candidate except preserving existing alpha49 code.
- **Validation state**: alpha50 allocated; **Code not yet written** at checkpoint time. No CI/artifact/runtime evidence yet.

## Alpha49 implementation retained

1. Current top-right chat menu includes exact-ID Pull / Reload / Rename / Export.
2. `CEFeatures renameConversationID:title:` builds the rename record from the frozen exact ID and rechecks current context immediately before PATCH.
3. `CEForegroundWindows()` is a public-UIKit surface helper only, not identity state.
4. Project-header presentation and Reload UI evidence search foreground visible windows instead of only `CEKeyWindow()`.
5. Request-only Reload success remains prohibited.
6. Interrupted-generation recovery remains unchanged; no speculative `/resume`, retry/watchdog/timer/status override exists.

## Identity architecture retained

- Only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity into the sole long-lived `CEConversationContext`.
- Generic/background request recency, arbitrary UUID-looking UI/config strings and title-only matching are not **current-conversation** execution authority.
- Current top-right chat menu freezes exact ID for Pull/Reload/Rename/Export and actions fail closed when exact context changes.
- Sidebar/non-current menu actions are row-scoped management actions, not active-conversation actions. They may resolve a catalog candidate set from the selected row's presentation title, but ambiguity must remain explicit and cannot update `CEConversationContext`.
- Share remains validation-only and is never silently invoked for discovery.
- Old conversation-tool floating UI stays retired. Percentage UI is a separate task and untouched.

## Required alpha50 real-device acceptance

1. Current top-right `...` menu remains unchanged and functional.
2. Long-press a conversation row in the list: enhancer `重命名会话` and `导出 Markdown` are present; Pull/Reload are absent.
3. Rename/export a row that is not the currently open chat and verify the selected row is the one affected/exported.
4. Test two conversations with the same title: plugin must not silently pick one; explicit candidate choice or fail-closed behavior is required.
5. Opening a sidebar menu must not change the current conversation ID used by the top-right current-chat actions.
6. A↔B exact-current Pull/Reload/Rename/Export safety remains unchanged.
7. Project-header title/gear and Reload UI-proof acceptance remain pending alpha49/50 lineage items unless separately tested.

## Rejected / do-not-repeat

- using current `CEConversationContext` as the sidebar row target;
- adding Pull/Reload to sidebar menus;
- arbitrary UUID-shaped UI/config identifiers as conversation IDs;
- silently choosing the newest/first record among duplicate titles;
- restoring alpha46 candidate resolution as current-chat execution authority;
- mutating active context from sidebar touch/title evidence;
- request observed == Reload completed;
- page/UI rebuilt == interrupted generation recovered;
- speculative resume/retry/watchdog without runtime evidence;
- generic latest-request foreground authority;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- private Swift class hard-coding;
- touching percentage-owned files in this work.

## Next exact action

Implement the minimal sidebar/non-current menu branch in `CEEnhancerUI.mm`, preserve alpha49 current-header behavior, synchronize alpha50 version/build/workflow identity, run isolated CI, then update this checkpoint and durable docs with exact commit/run/artifact evidence. Runtime remains pending until the user tests the exact alpha50 artifact.