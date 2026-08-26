# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition test branch, but no recognition candidate is accepted until real-device evidence proves both no cross-targeting and reliable exact-current identification.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha45-visible-button-guard`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `037b4aba99b45f30e04a8f9714231a545a0137c2`; Actions bookkeeping `f28c7f56cfaea48f35cb98ecb20490686f36b54f`; current branch head `c902d0f1a76d65dd3ba2232dd88eae2b1ac269d8` (post-CI trigger cleanup only). Product source is unchanged from the tested head.
- Alpha45 retains alpha44's safety: generic official/background conversation requests do not mutate foreground `CEConversationContext`; stale global ID fallback remains prohibited.
- CI passed: run `32939338703`, job `98086902604`. Artifacts: package id `9595962373`, dylib id `9595962949`.
- New real-device evidence on 2026-08-26: in the current project chat, Reload can still refuse with `无法确认当前可见会话，已取消重载。`, so alpha45 remains **not accepted** due false-negative current recognition.
- In the same supplied 7.2s recording, opening the top-right conversation menu and choosing `重命名会话` prefills the correct current title `优化会话识别`. Current source proves this visible Rename is enhancer-injected together with `导出 Markdown`, and both use the same menu-scoped `CECandidatesForSourceView(...)` candidate resolver. Therefore the recording proves menu-scoped candidate resolution can succeed where global current-visible proof fails, but it does **not** yet prove a native exact conversation ID is exposed.
- Status: **Runtime/manual partially tested; not accepted.** No successor candidate has been allocated because the user explicitly requested analysis/instrumentation design before more product code.

### Rejected `0.1.0-alpha44-current-conversation-guard`

- Alpha44 addressed the proven network-driven identity contamination and passed Actions `32937976994` with artifacts.
- Real-device result: floating action button was not visible because its lifecycle was coupled to `CEConversationContext.conversationID`.
- Alpha44 is rejected as a usable candidate; its cross-conversation stress acceptance was not completed.

### Rejected `0.1.0-alpha42-project-conversation-title`

- Actions `32855687010` passed and artifacts were produced, but extended real-device use proved Pull Latest and Reload could cross/wrong conversations.
- Source later proved generic network request IDs could overwrite foreground identity.
- Project-header conversation-title replacement also had no visible effect. Cosmetic header work remains deferred.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 is stacked on the rejected alpha42 recognition state.
- Its percentage-specific work remains a separate Active task. The current screenshot's percentage bubble is therefore a parallel floating surface; if the user ultimately wants **all** floating UI hidden, that change must be coordinated rather than silently made in recognition work.

### Earlier alpha41 / alpha40 / alpha39

- Alpha41 was superseded pre-runtime after synthetic header text was found capable of feeding identity paths.
- Alpha40 produced artifacts but was not separately accepted before the alpha42 lineage failed.
- Alpha39 exact-current reload contract remains architectural history, but the base lineage has known stale/current-conversation problems.

## Current architecture / evidence

1. `CEBootstrap` — startup owner.
2. `CECore` / `CEConversationContext` — sole long-lived active-conversation state owner.
3. `CEContextResolver` — current visible UIKit/catalog-backed proof; generic network task resume is no longer foreground authority.
4. `CENetworkObserver` — passive official-network observation/template/event/catalog input; observed requests do not determine foreground identity.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/project catalog.
7. `CEEnhancerUI` — host UIKit integration and menu augmentation. Current code wraps `UIContextMenuConfiguration` and adds enhancer `重命名会话` + `导出 Markdown`; those actions use menu-scoped `CECandidatesForSourceView(...)`.
8. Features/Export/Diagnostics consume those owners.

## Current development direction

- The priority remains exact conversation targeting, but the design question has shifted: **stop trying to make a continuously guessed global “current conversation” do all work if the host's conversation menu can provide stronger action-time evidence.**
- Investigate a menu-scoped model where Pull Latest / Reload / Export Markdown operate from an immutable target captured when the current-chat menu is built. This target is ephemeral evidence, not a second long-lived authority; exact proven IDs may update `CEConversationContext`.
- Do not execute from title alone. Duplicate-title conversations must be part of acceptance.
- Before moving actions or removing floating UI, build a sanitized persistent diagnostic trace that can survive app relaunch and capture menu configuration/source identifiers, original menu action identifiers, explicit IDs/candidates, lifecycle, relevant sanitized conversation endpoint paths/statuses, and exact target chosen by enhancer actions.
- Diagnostic persistence must never include Authorization, Cookie, account IDs, raw request templates/bodies, response bodies or message contents.
- Required capture should include normal chats, project chat, repeated A↔B, duplicate titles, and force-close/relaunch directly into the last conversation.
- Project-header title replacement remains deferred.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change.
- No verified automated unit/UI test suite exists; CI build success is not runtime proof.
- Current `CELastTouchedView` / title hints and title matching are heuristic; they are useful diagnostic evidence but cannot be final execution authority.
- Top-right current-chat menu and sidebar/long-press menu may look similar while exposing different configuration/source evidence; diagnostics must distinguish them before assuming equivalence.
- Correct prefilled title does not prove exact ID, especially with duplicate titles.
- Generic/background network traffic remains correlation evidence only, not foreground authority.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.