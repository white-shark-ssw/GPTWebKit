# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha51-sync-latest-rate-limit`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `bbc8696d7c11f2d6030d7e44cdc3c979f38dba77`; CI bookkeeping `798631ce879dd32e5f774659789d03c3772ad1f5`; current branch head `8722e5f2a0a7bd6513997825b1a25991e5d342b7` after workflow-trigger cleanup.
- CI passed: Actions `33000977913`, job `98282430781`.
- Artifacts: package id `9618537159`; dylib id `9618537770`.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Alpha51 behavior

- Current top-right action is renamed from `拉取最新消息` to **`同步最新消息`**.
- Sync keeps the immutable exact-current conversation ID contract and rechecks the same ID after the asynchronous server fetch and before Reload handoff.
- A short-lived in-flight guard prevents repeated taps from creating concurrent Sync GET requests.
- `CEAPIClient` no longer automatically retries HTTP 429. A 429 ends that request and reports numeric `Retry-After` when available, otherwise asks the user to retry later. Existing non-429 transport/5xx/auth retry behavior is unchanged.
- The previous `1/3` text was plugin retry count after a server 429, not an OpenAI quota counter. HTTP 429 itself is server-side rate limiting; short-window request bursts are a plausible trigger, but exact OpenAI account/IP/endpoint thresholds are undocumented.
- Sync does not claim page success from the plugin JSON GET. If the server still reports generation in progress, no forced refresh occurs. If the latest server result is finished and the exact current ID is unchanged, Sync cancels stale tracked streams using the pre-existing safety path and invokes existing exact-current manual Reload. Final Reload success still requires same-ID request plus UI rebuild proof.
- No Catalog paging change was made because no current runtime evidence attributes a specific 429 to Catalog request volume.

## Existing runtime findings retained

### Exact-current/menu architecture

- Explicit `POST /backend-api/conversation/init` body `conversation_id` remains the proven foreground existing-chat identity signal.
- Current top-right Sync / Reload / Rename / Export freeze that exact ID and fail closed if context changes.
- Sidebar Rename/Export remain row-scoped catalog-candidate actions and do not borrow active context.

### Project header — paused

- Alpha50 trace `A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9` proves exact identity/title acquisition but rejects the current UIKit `聊天 UILabel + nearby title UILabel` presentation target on app `1.2026.202`.
- User explicitly asked to pause this problem. Alpha51 does not modify project-title code.

### Reload / generation recovery

- Reload request delivery is not Reload completion; existing request+UI proof remains required.
- Page rebuild is not proof that an interrupted generation recovered. No speculative `/resume`, watchdog or generation retry was added.

## Current architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation authority.
3. `CENetworkObserver` — passive host-network observation; only validated explicit `conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated request owner; HTTP 429 is terminal for the current enhancer request rather than an automatic retry trigger.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — host menu/UI integration.
7. `CEConversationUIReloadEvidence` — ephemeral Reload UI proof.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha51 did not modify percentage-owned source/checkpoint.

## Known issues / next evidence

- Alpha51 Sync/rate-limit behavior requires real-device validation; CI/artifact success is not runtime proof.
- Sidebar Rename/Export selected-row acceptance and Reload UI-proof remain pending.
- A broader Catalog traffic reduction requires sanitized internal request-count/status evidence before attribution is treated as fact.
- Project-header presentation remains paused by user.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.