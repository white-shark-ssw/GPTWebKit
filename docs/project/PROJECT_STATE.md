# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition candidate is Stable/Frozen yet.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha48-reload-ui-title`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `e2b133f0ba050b485e89129e4fe0ecb9bbee2343`; Actions bookkeeping `7b2d9d9e709e431ec414b269bd72b4b33a092001`; current head `17f76c8428dad41484641b9dcf23a78935dbc32f` after workflow-trigger cleanup only.
- CI passed: Actions `32973529739`, job `98192604072`.
- Artifacts: package id `9608529953`, dylib id `9608530563`.
- Alpha48 retains alpha47 exact identity/menu targeting and changes two behaviors:
  1. Reload success now requires exact same-ID official request delivery **plus** public-UIKit evidence that the current message/conversation view rebuilt/refreshed. Request-only completion cannot report success.
  2. For the already-proven exact current conversation ID, the official current-chat menu title may refresh presentation metadata. Project-chat top header then replaces the project name with that exact conversation title and adds a small gear marker. The synthetic header never participates in identity evidence.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

### Alpha47 exact-menu-target — partially tested, superseded for reload semantics

- Alpha47 established the exact-ID architecture: explicit `POST /backend-api/conversation/init` body ID → sole `CEConversationContext` → immutable current-header menu target for Pull/Reload/Export; old conversation-tool floating button retired; percentage task untouched.
- Actions `32969623709`, job `98180033708`, artifacts produced.
- Real-device feedback: Reload could report success even when the page did not visibly appear to reload. Source confirmed its success condition was only `CEManualReloadRequestSeen(...)`, so an official request was proof of route/request delivery, not proof that the current page actually reloaded.
- This is the direct evidence for alpha48's request+UI completion rule.

### Alpha46 instrumentation — evidence complete

- Alpha46 trace captured 784 events across 2 launches / ~239 seconds including normal/project chats, repeated switching, duplicate-title chats, Share flows and force-close/relaunch.
- 8 official `POST /backend-api/share/create` requests across 6 unique conversations carried explicit body `conversation_id`. Two same-title `测试会话` chats had distinct exact IDs.
- For 7/7 Share events with a preceding explicit `POST /backend-api/conversation/init` body ID, the latest explicit init ID matched the Share target. Cold relaunch also restored matching exact ID before user interaction.
- 13 UUID-looking menu configuration IDs had zero intersection with the real conversation IDs. Arbitrary UUID syntax is not identity evidence.

### Older recognition candidates

- Alpha45: not accepted because normal project-chat Reload could false-negative current visible proof.
- Alpha44: rejected because the floating tool disappeared when identity was unknown.
- Alpha42: rejected because Pull/Reload could cross conversations; generic observed network traffic had been allowed to overwrite foreground identity.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 remains stacked on rejected alpha42 recognition.
- User explicitly instructed the current recognition work to leave percentage behavior alone. Alpha48 does not touch percentage-owned files or that checkpoint.

## Current architecture / evidence

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole long-lived active-conversation state owner.
3. `CEContextResolver` — no longer performs periodic UI/title identity guessing; compatibility getter only returns current exact owner.
4. `CENetworkObserver` — generic passive official-network observation/template/catalog input. Only the specifically validated explicit `conversation/init` request-body ID may promote foreground identity into the existing context owner.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/project catalog and presentation title owner.
7. `CEEnhancerUI` — host UIKit/menu integration, exact current-menu action capture, project-header presentation.
8. `CEConversationUIReloadEvidence` — public-UIKit ephemeral snapshot helper for Reload completion evidence; not an identity or persistent state owner.
9. `CEConversationIdentityTrace` — optional sanitized runtime evidence recorder; not an identity authority.

## Current behavior contracts

- Current-conversation Pull/Reload/Export use immutable exact ID captured by the top-right current-chat menu. If exact current context changes before tap, action cancels.
- Generic/background request recency, title-only matching and arbitrary UI UUIDs cannot decide the target.
- Official Share remains validation-only and is never silently invoked for discovery.
- **Reload request delivery is not Reload completion.** A success message requires both exact same-ID request proof and current message-view rebuild/refresh proof.
- If request proof exists but UI rebuild cannot be proven, the result must explicitly remain unconfirmed rather than saying success.
- Project-header rewritten title is presentation-only. It may be derived from the already-proven exact target's official menu/catalog title and displayed with a gear marker, but it cannot feed identity logic.
- The retired conversation-tool floating button stays removed; percentage UI belongs to the parallel task and is untouched.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change; current evidence is tied to the tested app/runtime environment.
- No automated unit/UI suite is verified; CI success is not runtime proof.
- Alpha48's public-UIKit UI-rebuild proof deliberately fails closed. If the host updates model data while reusing the same scroll and visible message view objects, it may produce a false-negative “request sent but page refresh not confirmed”; that must be refined from real-device evidence rather than reverting to request-only success.
- Absolute “100% forever” cannot be inferred from one host version. Unsupported states must fail closed instead of guessing another conversation.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.