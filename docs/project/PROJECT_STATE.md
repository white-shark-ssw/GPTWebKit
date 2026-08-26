# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition fix is accepted yet.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha46-conversation-identity-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `fc78d7d525969699fbd15a3f180e563e93e6d424`; Actions bookkeeping `a99a9b99ec9c26e3537ee5a242f0cfa7c4764f88`; post-CI cleanup head `96d845e7d750ea178ff73c12faed115dff33d14c`.
- CI passed: Actions `32950198256`, job `98119660626`. Artifacts: package `9599824714`, dylib `9599825427`.
- Alpha46 is instrumentation-only and **has now completed its real-device trace purpose**.
- User trace `conversation-identity-871F676C-DD34-40E3-B7FB-561BB0165581.log` contains 784 structured events across 2 app launches / ~239 seconds and includes normal chats, project chats, repeated switching, duplicate-title chats, Share flows and force-close/relaunch.
- 8 official `POST /backend-api/share/create` requests across 6 unique conversations carried explicit body `conversation_id` values. Two separate conversations both titled `测试会话` produced distinct exact IDs, proving Share knows the exact conversation independently of title.
- For every captured Share with a preceding explicit `POST /backend-api/conversation/init` body ID in the same recorded process (7/7), the latest explicit init ID exactly matched the later Share target. Explicit init also tracked project chats and duplicate-title chats. No contradictory/background explicit-init ID appeared in this trace.
- Cold relaunch emitted the restored conversation's exact ID before user interaction through `conversation/init`, `beacons/home?conversation_id`, then matching prepare/detail traffic; later Share confirmed the same ID.
- Top-right menu/source public structural evidence did **not** expose the backend conversation ID. Parent menu title was correct, but source scans had no explicit conversation ID and action identifiers had no UUID target.
- 13 unique UUID-looking menu configuration identifiers had zero intersection with the 7 real conversation IDs observed in network evidence. Current generic UUID extraction therefore mislabels structural UI UUIDs as conversation IDs and must not be used as identity proof.
- Status: **Code written → CI passed → Artifact produced → Runtime/manual instrumentation tested.** This is evidence for the next product candidate, not a fix acceptance.

### Not accepted `0.1.0-alpha45-visible-button-guard`

- CI/artifact succeeded, but current-project Reload could still fail closed with `无法确认当前可见会话，已取消重载。`.
- Alpha46 now confirms the long-lived global context can be stale even while the correct menu title is visible.

### Rejected `0.1.0-alpha44-current-conversation-guard`

- Removed unsafe generic network writers but made the floating entry disappear when identity was unproven.

### Rejected `0.1.0-alpha42-project-conversation-title`

- Extended real-device use proved Pull Latest / Reload could cross conversations; generic observed conversation traffic had been allowed to overwrite foreground identity.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 remains stacked on rejected alpha42 recognition.
- Percentage-specific work remains separate. If all floating UI is later retired, coordinate its percentage bubble with that task.

## Current architecture / evidence

1. `CEBootstrap` — startup owner.
2. `CECore` / `CEConversationContext` — sole long-lived active-conversation state owner.
3. `CEContextResolver` — UIKit/catalog-based proof path; currently too weak for final action targeting.
4. `CENetworkObserver` — generic passive observer; arbitrary request recency is not identity authority.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/catalog owner.
7. `CEEnhancerUI` — host UIKit/menu integration.
8. `Diagnostics/CEConversationIdentityTrace` — alpha46 evidence recorder only, not an identity authority.

## Current development direction after alpha46

- The strongest non-side-effect runtime signal found is **`POST /backend-api/conversation/init` with an explicit request-body `conversation_id`**. Alpha46 validates it against official Share across repeated switching, project chats, duplicate titles and cold relaunch.
- This does **not** restore the old “latest network request wins” design. Only a semantically proven endpoint/field may become foreground evidence; generic GET detail/background traffic remains passive.
- Official `POST /backend-api/share/create` body `conversation_id` is the best current action-time ground-truth oracle, but Share is side-effectful and must never be silently invoked just to identify a chat.
- Arbitrary UUID-looking UIKit/menu identifiers are not conversation IDs. Identity parsing must be source/field-aware rather than shape-only.
- A future menu action should capture an immutable exact ID at menu-build time and pass that target directly to Pull/Reload/Export. Menu title is presentation/consistency evidence only, never duplicate-title identity authority.
- After this exact-ID path is implemented and accepted on device, Pull/Reload/Export can move into the conversation menu and the current floating action tool can be retired. Header-title cosmetics remain deferred.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change; runtime evidence is for app version `1.2026.202` and the tested iOS environment.
- No automated unit/UI suite is verified; CI success is not runtime proof.
- Absolute “100% forever” cannot be inferred from one app version, so unsupported states must still fail closed rather than guess.
- Share request creation is a side effect and is not an acceptable hidden identity lookup.
- Generic UUID regex extraction is unsafe on arbitrary UI/configuration strings.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.