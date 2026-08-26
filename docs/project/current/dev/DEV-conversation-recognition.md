# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Pull / Reload / Export / Rename 不串会话；同时保留侧栏会话行的安全 Rename / Export、完善 Reload 完成语义和项目会话标题展示。
- **Acceptance invariant**: **当前会话 Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏长按 Rename / Export 必须作用于被长按的会话行，不得借用当前页面 ID；若只能得到同名候选，必须显式选择或失败关闭，禁止猜测。Reload 请求发生不等于 Reload 完成；插件生成标题只能用于 presentation，永远不能反向成为 identity evidence。**

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged after the alpha50 runtime trace.
- **Working branch / PR**: `feat/conversation-recognition` at `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR remains open/draft/mergeable.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned source/checkpoint untouched.
- **Candidate uniqueness**: alpha43 remains reserved by the parallel task; recognition alpha46/47/48/49 are historical allocations. alpha50 remains the current unique candidate.

## Authoritative alpha50 runtime evidence — 2026-08-27

Trace: `conversation-identity-A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9.log`, enhancer `0.1.0-alpha50-sidebar-menu-actions`, app `1.2026.202`.

1. User reports the project conversation header still does not change to the real conversation title.
2. The final entered conversation is independently proven as `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1`:
   - `POST /backend-api/conversation/init` carries that exact ID;
   - `IDENTITY-INIT` accepts the same ID with title `会话百分比v1`;
   - subsequent `prepare` and conversation-detail requests use the same ID;
   - the top-right menu repeatedly exposes `menuTitle=会话百分比v1` and captures the same exact target.
3. Therefore the failure is **not** conversation identity or title acquisition. `HEADER-TITLE` records the correct presentation title, but that log category only proves the title was learned; it does not prove a visible header view was found or modified.
4. The actual project-chat screen repeatedly logs the foreground content `UIWindow` with `topLabelCount=0` immediately after exact `conversation/init` and again several seconds later. Across the whole trace there are **zero `HEADER-TARGET` events**.
5. Current source requires `CEProjectConversationTitleLabel(...)` to find a top-area UIKit `UILabel` whose exact text is `聊天`, then find a nearby title `UILabel`. Since no such UIKit labels exist on the actual project-chat screen, `CEProjectConversationTitleTarget()` returns nil and `refresh:` exits without modifying anything.
6. The top-right menu source itself is a SwiftUI `ViewBasedUIButton` host class. When the menu/share presentation is visible, trace can see UIKit labels such as `分享` and `会话百分比v1`, but still no `聊天` label matching the required project-header pair. This strongly indicates the visible project header is SwiftUI-hosted / not exposed as the mutable `UILabel` pair assumed by alpha49/50. Do not hard-code the observed private SwiftUI class name.
7. This runtime evidence rejects the current **UILabel replacement strategy** for the project header on this host build. Re-scanning more foreground windows for the same UILabel pair will not fix the observed failure.

## Authoritative alpha49 runtime evidence — 2026-08-26

- User confirms the custom options shown from the **current conversation top-right `...` menu are correct** in alpha49.
- User reports a coverage regression: **long-pressing a conversation in the conversation list no longer shows enhancer custom options** and requests restoring only `重命名会话` and `导出 Markdown` there.
- Alpha49 source explains the regression: `CEAugmentedChildrenForSource(...)` returned the original menu whenever `CEIsCurrentConversationHeaderSource(...)` was false. That protected current-ID Pull/Reload/Rename/Export from leaking into sidebar menus but also removed the older sidebar Rename/Export UX.
- This runtime result did **not** establish project-header title/gear or Reload UI-proof success.

## Current candidate — alpha50

- **Candidate**: `ENH-0.1.0-alpha50-sidebar-menu-actions` / product `0.1.0-alpha50-sidebar-menu-actions`.
- **Build/test source**: `44b7baf84458c19c963ce0a7ee0d869da28dfe08`.
- **Actions**: run `32984372907`, job `98228416235` — completed **success**.
- **CI bookkeeping**: `7988e2c06c38c419885f815e4960a892c08fe28f`.
- **Current branch head**: `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`; compared with tested source, only `.github/latest-enhancer-run-id` plus removal of the temporary feature-branch CI trigger differ. Product source is unchanged from the tested commit.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha50-sidebar-menu-actions`, id `9612825155`, digest `sha256:d19595daa76d7ecc1eb5432a68c6cf70ceb77912c094ac5aad0ecead45c5a983`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha50-sidebar-menu-actions-dylib`, id `9612825334`, digest `sha256:5580d466418c2e6ba7c6ad7eab46861e0efb8e65ca59b489a58e6356825ca8b7`.
- **Validation state**: **Code written → CI passed → Artifact produced → Runtime/manual partially tested.** Project-header title/gear is **failed / not accepted** on app `1.2026.202`; sidebar Rename/Export and Reload UI-proof acceptance are still pending. Nothing is Stable/Frozen.

## Alpha50 implementation

1. **Current top-right menu unchanged**: alpha49 immutable exact-current ID path remains Pull / Reload / Rename / Export + trace. It still uses `CEConversationContext` only after the validated `conversation/init` signal and still fails closed if context changes.
2. **Sidebar/non-current conversation menu restored**: conversation-like menus outside the current top header receive only `重命名会话` and `导出 Markdown`. Pull / Reload / identity-trace are intentionally absent.
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

## Required next runtime / implementation evidence

1. **Do not continue the current UILabel-pair search as the project-header fix.** Alpha50 trace proves the actual project-chat top area has no matching UIKit UILabel target.
2. Before changing presentation code, capture the top-area public accessibility elements (frame, label/value/identifier and public class only) while the project header is visible and no menu/share overlay is open. Determine whether the visible project-name/`聊天` presentation has a stable accessibility frame even though it is not a UILabel.
3. If a stable public frame exists, prefer a non-interactive UIKit presentation overlay anchored to that proven frame rather than hard-coding private SwiftUI classes. The overlay must remain presentation-only and never feed identity.
4. If no public frame/evidence exists, stop and reassess instead of guessing coordinates or adding a polling timer.
5. Sidebar Rename/Export real-device acceptance remains pending: verify a non-current row and duplicate-title behavior.
6. Reload UI-proof and interrupted-generation recovery remain separate pending issues.

## Rejected / do-not-repeat

- continuing to assume the project header is a mutable UIKit `UILabel` pair after alpha50 trace showed zero top labels / zero header target on the actual chat screen;
- hard-coding observed private SwiftUI class names;
- guessing fixed title coordinates without runtime frame evidence;
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
- touching percentage-owned files in this work.

## Next exact action

Explain the alpha50 header failure from the uploaded trace. Do **not** allocate another candidate or change product code until the user asks to proceed. If proceeding, first extend the existing sanitized trace to capture the top-area public accessibility element frames on the real project-chat screen; then choose an evidence-backed presentation target/overlay. Sidebar and Reload acceptance remain separate.