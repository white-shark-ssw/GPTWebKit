# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition candidate is Stable/Frozen yet.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha50-sidebar-menu-actions`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `44b7baf84458c19c963ce0a7ee0d869da28dfe08`; Actions bookkeeping `7988e2c06c38c419885f815e4960a892c08fe28f`; current branch head `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac` after workflow-trigger cleanup only.
- CI passed: Actions `32984372907`, job `98228416235`.
- Artifacts: package id `9612825155`, dylib id `9612825334`.
- User runtime on alpha49 confirmed the current conversation top-right custom menu works, but conversation-list long-press lost enhancer actions because non-header menus were intentionally skipped.
- Alpha50 preserves the alpha49 top-right exact-current action path and restores **only** sidebar/non-current `重命名会话` + `导出 Markdown`.
- Sidebar target resolution is row-scoped: it derives a known `CECatalog` candidate set from the touched row/menu presentation title, never borrows or mutates `CEConversationContext`, never treats menu/config UUID syntax as identity, and requires explicit selection when titles are duplicated.
- Pull / Reload remain absent from sidebar menus. Existing project-header, Reload UI-proof and interrupted-generation behavior are otherwise unchanged.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

### Alpha49 — partial runtime / superseded for sidebar coverage

- Alpha49 Actions `32980682467`, artifacts produced.
- User confirms current conversation top-right `...` custom options are correct.
- Conversation-list long-press did not include enhancer options. Source confirmed `CEAugmentedChildrenForSource(...)` returned early for every non-header menu. Alpha50 restores only safe row-scoped Rename/Export there.
- Alpha49 project-header title/gear and Reload UI-proof changes are not accepted from this runtime result and remain pending in the alpha50 lineage.

### Alpha48 — runtime investigation / not accepted

- Exported trace `6CC3B3D6-2F4F-40A1-9D84-CABB7D0C7F3B` kept the exact Reload target stable and showed same-ID `conversation/init → f/conversation/prepare → conversation detail`.
- User visually saw page refresh while alpha48 logged `baselineUI=unproven`; the old UI evidence source false-negatived.
- Correct exact-ID menu title was available while project header still showed project name/no gear.
- A prior interrupted turn remained at `正在思考`; the trace began after disconnect, so official generation recovery remained unproven.

### Alpha46 identity instrumentation — evidence complete

- Explicit `POST /backend-api/conversation/init` body `conversation_id` tracked foreground existing-chat navigation across normal/project chats, A↔B, duplicate titles and cold relaunch.
- Share-create body IDs independently matched the latest explicit init target 7/7 in captured cases.
- UUID-looking menu/configuration IDs had zero intersection with real conversation IDs.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; head remains `ddd5829b563a9191ad2687378123d9e53fbb232d`.
- Current recognition work leaves percentage-owned source/checkpoint untouched.

## Current architecture / evidence

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole long-lived active-conversation state owner; `CEForegroundWindows()` is a UIKit surface helper only.
3. `CEContextResolver` — no periodic UI/title identity guessing; compatibility getter only returns current exact owner.
4. `CENetworkObserver` — generic official-network observation/template/catalog input; only validated explicit `conversation/init` body ID may promote foreground identity.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/project catalog and presentation title owner.
7. `CEEnhancerUI` — host UIKit/menu integration; exact current-header actions plus row-scoped sidebar Rename/Export.
8. `CEConversationUIReloadEvidence` — ephemeral public-UIKit Reload completion evidence.
9. `CEConversationIdentityTrace` — optional sanitized runtime evidence recorder; not identity authority.

## Current behavior contracts

- Current top-right Pull / Reload / Rename / Export use immutable exact conversation ID captured from the current-chat menu and cancel if exact context changes.
- Current Rename additionally rechecks exact context immediately before PATCH.
- Sidebar/non-current Rename / Export are selected-row management actions. They must not use the active current conversation ID as the row target. A row title may only produce a catalog candidate set; duplicate titles require explicit selection.
- Generic/background request recency, arbitrary structural UUIDs and title-only inference cannot decide current-chat action identity.
- Official Share remains validation-only and is never silently invoked for discovery.
- **Reload request delivery is not Reload completion.** Same-ID request proof plus real UI rebuild/refresh proof are required before success.
- **Page/UI rebuild is not interrupted-generation recovery.** A reloaded page stuck at `正在思考` is not considered recovered without separate stream/status evidence.
- Project-header rewritten title is presentation-only and cannot feed identity logic.
- Retired conversation-tool floating UI stays removed; percentage UI belongs to the parallel task and is untouched.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change; current evidence is tied to the tested app/runtime environment.
- No automated unit/UI suite is verified; CI success is not runtime proof.
- Alpha50 sidebar menu targeting is Code/CI/Artifact evidence only until device-tested, especially non-current rows and duplicate titles.
- Project-header title/gear and Reload UI-proof behavior remain runtime pending in the alpha50 lineage.
- Interrupted-generation recovery still requires a trace started before prompt send/disconnect.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.