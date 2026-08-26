# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition candidate is Stable/Frozen yet.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha49-exact-rename-ui-target`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `3f3a04715e93755c1c04b4ca826aad2488c2a9a1`; Actions bookkeeping `0e1bb6a72bc41f05ff5addceeffa3164c413b817`; current branch head `9534ddb77bc43a979e34bd69b040d85ff38501dd` after workflow-trigger cleanup only.
- CI passed: Actions `32980682467`, job `98216287227`.
- Artifacts: package id `9611305133`, dylib id `9611306138`.
- Alpha49 retains the exact `conversation/init` → `CEConversationContext` → immutable current-menu target architecture and makes three evidence-backed changes:
  1. restores enhancer `重命名会话` to the current top-right menu and rechecks the exact current ID again immediately before PATCH;
  2. project-header presentation searches visible windows of the foreground-active scene instead of only `CEKeyWindow()`, with trace-only top-window/UILabel evidence when no target is found;
  3. Reload UI evidence searches all visible foreground-scene windows for the dominant conversation-like scroll surface before taking the baseline/rebuild snapshot, addressing alpha48's `baselineUI=unproven` while the action was invoked from a context menu.
- Request-only Reload success remains prohibited. Interrupted-generation recovery is intentionally unchanged because the existing trace started after the disconnect and does not prove the official recovery lifecycle.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

### Alpha48 — runtime investigation / not accepted

- Alpha48 Actions `32973529739`, artifacts produced.
- Exported trace `6CC3B3D6-2F4F-40A1-9D84-CABB7D0C7F3B` kept the exact target stable and showed same-ID `conversation/init → f/conversation/prepare → conversation detail` during Reload.
- User visually saw the page refresh, but alpha48 logged `baselineUI=unproven` and never proved UI rebuild. The old UI evidence source therefore false-negatived.
- The exact menu title was available (`轮播图优化v1`) but the project header still showed project name/no gear. Presentation target discovery/application remained broken.
- The prior interrupted turn stayed at `正在思考` after page reload; trace began after the original disconnect and did not prove any official stream recovery route.
- Alpha47's exact-menu rewrite also accidentally omitted the enhancer Rename action; alpha49 restores it using exact-ID semantics.

### Alpha46 identity instrumentation — evidence complete

- Alpha46 trace established explicit `POST /backend-api/conversation/init` body `conversation_id` as the foreground existing-chat signal across normal/project chats, A↔B, duplicate titles and cold relaunch.
- Share-create body IDs independently matched the latest explicit init target 7/7 in the captured cases.
- UUID-looking menu/configuration IDs had zero intersection with real conversation IDs, proving UUID syntax alone is not identity evidence.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 remains stacked on older recognition source.
- Current recognition work explicitly leaves percentage-owned source/checkpoint untouched.

## Current architecture / evidence

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole long-lived active-conversation state owner; `CEForegroundWindows()` is a shared UIKit surface helper only, not identity state.
3. `CEContextResolver` — no periodic UI/title identity guessing; compatibility getter only returns current exact owner.
4. `CENetworkObserver` — generic official-network observation/template/catalog input. Only the validated explicit `conversation/init` body ID may promote foreground identity into the existing context owner.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/project catalog and presentation title owner.
7. `CEEnhancerUI` — host UIKit/menu integration, immutable exact current-menu actions, project-header presentation.
8. `CEConversationUIReloadEvidence` — ephemeral public-UIKit Reload completion evidence; alpha49 searches the foreground scene rather than assuming the key window is the conversation surface.
9. `CEConversationIdentityTrace` — optional sanitized runtime evidence recorder; not an identity authority.

## Current behavior contracts

- Pull / Reload / Rename / Export use an immutable exact conversation ID captured by the top-right current-chat menu. Actions cancel when the sole exact current context no longer matches.
- Rename additionally rechecks exact context immediately before the PATCH after the user finishes editing the title.
- Generic/background request recency, title-only matching and arbitrary UI UUIDs cannot decide the action target.
- Official Share remains validation-only and is never silently invoked for discovery.
- **Reload request delivery is not Reload completion.** Same-ID request proof plus real UI rebuild/refresh proof are required before success.
- **Page/UI rebuild is not interrupted-generation recovery.** A page that reloads but remains at `正在思考` is not considered recovered without separate stream/status evidence.
- Project-header rewritten title is presentation-only and cannot feed identity logic.
- The retired conversation-tool floating UI stays removed; percentage UI belongs to the parallel task and is untouched.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change; current evidence is tied to the tested app/runtime environment.
- No automated unit/UI suite is verified; CI success is not runtime proof.
- Alpha49's multi-window UIKit target discovery is code/CI/artifact evidence only until device-tested. If the host header/messages are not represented by the traversed UIKit surfaces, runtime trace must establish that before any private-class or timer approach is considered.
- Interrupted-generation recovery still requires a trace started before prompt send/disconnect.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.