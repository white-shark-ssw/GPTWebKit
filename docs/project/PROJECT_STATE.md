# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha53-refresh-path-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `b62878928816c40cbed8c11847a3ed7ae494adde`; CI bookkeeping `fa926ca61013292056e647f78d1d1677b608a72b`; post-CI cleanup head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- CI passed: Actions `33007145536`, job `98303728684`.
- Artifacts: package id `9621009139`, digest `sha256:500a38652acf60b50f15f5ace41ca31e68a198cda3acaf724f1547f88bbeb6b2`; dylib id `9621009533`, Actions archive digest `sha256:5648a23263eb0d7fa535387a5f7fcbe2d8622142f0bdfd862515be32bb7d59a8`.
- Extracted dylib: arm64 Mach-O, 594000 bytes, sha256 `78a38421fe04adba9774bb8e42947ea48120d2a61698359f04c31bdb6f6f86a2`.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Alpha52 runtime evidence now established

Trace `conversation-identity-585B0B11-C85D-4A19-BA16-4F55D56A320A.log`, app `1.2026.202`, captured a normal A → B → A navigation sequence.

- A → B: exact B `conversation/init` body ID, then within ~125 ms exact B `prepare` + detail GET + second prepare.
- B → A: an ID-less init/prepare project-loading sequence occurred first, followed by exact A `conversation/init`, then within ~125 ms exact A prepare + detail GET + second prepare.
- Exact foreground identity followed B then A correctly.
- This contrasts the alpha51 failed same-current custom-route refresh, which produced only same-ID detail GETs with zero exact `conversation/init`/exact `prepare` and no visible page rebuild.
- Therefore a detail GET alone is insufficient. Genuine navigation/rebuild correlates with an internal host navigation-state transition that produces `conversation/init → prepare → detail` traffic.
- The traffic is evidence of the state transition, not proof that enhancer-originated replay of those requests would mutate host UI.

## Alpha53 behavior

- Production Sync/Reload behavior remains alpha52: truthful refresh-request wording, exact-ID guards, request+UI completion proof, no repeated same-route delivery once same-ID request delivery is already proven, and terminal HTTP 429 behavior.
- Alpha53 only extends the existing user-started sanitized trace with `REFRESH-PATH` structural records for exact init/prepare/detail host requests.
- `REFRESH-PATH` records bounded public structural data: key/root/top/presented view-controller class names, navigation-controller stack count/visible controller class, and a sanitized bounded call-stack signature with raw addresses redacted.
- No auth/cookie/account/raw body/message content is persisted.
- No `/resume`, manual init/prepare replay, watchdog, alternate ID, History/sidebar/UIKit pop-push fallback, private-class hard-coding, Catalog throttling, project-header change or percentage change was added.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated explicit `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current request rather than a burst-retry trigger.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof, never identity authority.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority.

## Other retained runtime findings

- Alpha50 project-header trace proved exact identity/title acquisition but rejected the current UIKit `聊天 UILabel + nearby title UILabel` target on app `1.2026.202`; user has paused this feature.
- Reload request delivery is not Reload completion, and UI rebuild is not proof that an interrupted generation stream recovered.
- Sidebar Rename/Export selected-row acceptance and duplicate-title behavior remain pending real-device verification.
- Alpha51/52 terminal HTTP 429 behavior still has not been exercised by a trace containing 429.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha53 did not modify percentage-owned source/checkpoint.

## Next evidence

- Install alpha53 and record one combined trace: normal A → B → A, then one `同步最新消息` attempt on A, then export.
- Compare `REFRESH-PATH` caller/navigation signatures between genuine navigation and failed same-current refresh before implementing any production host refresh mechanism.
- This diagnostic sequence does not authorize History/sidebar navigation as production Reload behavior.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.