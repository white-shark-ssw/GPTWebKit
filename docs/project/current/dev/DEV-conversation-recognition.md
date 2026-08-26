# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Pull / Reload / Export / Rename 不串会话；同时保留侧栏会话行的安全 Rename / Export、完善 Reload 完成语义和项目会话标题展示。
- **Acceptance invariant**: **当前会话 Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏长按 Rename / Export 必须作用于被长按的会话行，不得借用当前页面 ID；若只能得到同名候选，必须显式选择或失败关闭，禁止猜测。Reload 请求发生不等于 Reload 完成；插件生成标题只能用于 presentation，永远不能反向成为 identity evidence。**

## Resume identity / conflict guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked before and after alpha50 CI and unchanged.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR remains open/draft/mergeable.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned source/checkpoint untouched.
- **Candidate uniqueness**: alpha43 remains reserved by the parallel task; recognition alpha46/47/48/49 are historical allocations. alpha50 is unique.

## Authoritative alpha49 runtime evidence — 2026-08-26

- User confirms the custom options shown from the **current conversation top-right `...` menu are correct** in alpha49.
- User reports a coverage regression: **long-pressing a conversation in the conversation list no longer shows enhancer custom options** and requests restoring only `重命名会话` and `导出 Markdown` there.
- Alpha49 source explains the regression: `CEAugmentedChildrenForSource(...)` returned the original menu whenever `CEIsCurrentConversationHeaderSource(...)` was false. That protected current-ID Pull/Reload/Rename/Export from leaking into sidebar menus but also removed the older sidebar Rename/Export UX.
- This runtime result does **not** establish project-header title/gear or Reload UI-proof success; those acceptance items remain pending.

## Current candidate — alpha50

- **Candidate**: `ENH-0.1.0-alpha50-sidebar-menu-actions` / product `0.1.0-alpha50-sidebar-menu-actions`.
- **Build/test source**: `44b7baf84458c19c963ce0a7ee0d869da28dfe08`.
- **Actions**: run `32984372907`, job `98228416235` — completed **success**.
- **CI bookkeeping**: `7988e2c06c38c419885f815e4960a892c08fe28f`.
- **Current branch head**: `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`; compare from tested source changes only `.github/latest-enhancer-run-id` plus removal of the temporary feature-branch CI trigger. Product source is unchanged from the tested commit.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha50-sidebar-menu-actions`, id `9612825155`, digest `sha256:d19595daa76d7ecc1eb5432a68c6cf70ceb77912c094ac5aad0ecead45c5a983`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha50-sidebar-menu-actions-dylib`, id `9612825334`, digest `sha256:5580d466418c2e6ba7c6ad7eab46861e0efb8e65ca59b489a58e6356825ca8b7`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing is Stable/Frozen.

## Alpha50 implementation

1. **Current top-right menu unchanged**: alpha49 immutable exact-current ID path remains Pull / Reload / Rename / Export + trace. It still uses `CEConversationContext` only after the validated `conversation/init` signal and still fails closed if context changes.
2. **Sidebar/non-current conversation menu restored**: conversation-like menus outside the current top header now receive only `重命名会话` and `导出 Markdown`. Pull / Reload / identity-trace are intentionally absent.
3. **Sidebar target never borrows current context**: sidebar selection does not read `CEConversationContext` as its row target and never writes/clears active context from touch/title evidence.
4. **No arbitrary UUID identity**: sidebar code does not parse `UIContextMenuConfiguration.identifier` or other structural UUID-looking strings as a conversation ID and does not call `CECatalog candidatesForView:`.
5. **Row-scoped presentation evidence**: touch-point/source accessibility label/value or menu title is accepted only when it exactly corresponds to a title already present in `CECatalog` (with narrow accessibility suffix stripping such as `，按钮` / `, button`). This title yields the candidate set only; it is not active-conversation authority.
6. **Duplicate titles remain explicit**: a unique title yields one exact catalog record. Multiple records with the same title are captured as the full candidate set and existing `CEFeatures renameCandidates:` / `exportCandidates:` presents explicit user choice. Empty candidate set fails closed through existing unresolved diagnostics.
7. The candidate set is frozen when the menu is built, so subsequent current-page changes do not retarget the sidebar action.
8. Existing alpha49 project-header / Reload UI evidence code is preserved. No percentage, generation recovery, `/resume`, retry/watchdog/timer or alternate-ID behavior was added.
9. Version/bootstrap/build/workflow identities are synchronized to alpha50. The temporary recognition-branch CI trigger was removed after the successful candidate build.

## Identity architecture retained

- Only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity into the sole long-lived `CEConversationContext`.
- Generic/background request recency, arbitrary UUID-looking UI/config strings and title-only matching are not **current-conversation** execution authority.
- Current top-right chat menu freezes exact ID for Pull/Reload/Rename/Export and actions fail closed when exact context changes.
- Sidebar/non-current menu actions are **row-scoped management actions**, not active-conversation actions. Presentation title may only produce a catalog candidate set; ambiguity remains explicit and cannot update `CEConversationContext`.
- Share remains validation-only and is never silently invoked for discovery.
- Old conversation-tool floating UI stays retired. Percentage UI is a separate task and untouched.

## Required alpha50 real-device acceptance

1. Current top-right `...` menu remains unchanged and functional.
2. Long-press a conversation row in the list: enhancer `重命名会话` and `导出 Markdown` are present; Pull/Reload are absent.
3. Rename/export a row that is not the currently open chat and verify the selected row is the one affected/exported.
4. Test two conversations with the same title: plugin must not silently pick one; explicit candidate choice or fail-closed behavior is required.
5. Opening a sidebar menu must not change the current conversation ID used by the top-right current-chat actions.
6. A↔B exact-current Pull/Reload/Rename/Export safety remains unchanged.
7. Project-header title/gear and Reload UI-proof acceptance remain pending lineage items unless separately tested.

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

Hand the exact alpha50 dylib to the user. Real-device test the current top-right menu plus a non-current sidebar row, including duplicate-title behavior. Record exact Rename/Export targeting results. Do not mark Stable/Frozen from CI/artifact evidence.