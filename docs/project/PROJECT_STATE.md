# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition test branch, but no recognition candidate is accepted until real-device stress testing passes.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha44-current-conversation-guard`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `668540cbabf300d08c929a1daa057ea4959f2f01`; Actions bookkeeping `ec8642391f40ae28a7f3dce8ddec983826ba76db`; current branch head `a4414cbdd5466cd7bb3d660f43039204dfb052dd` (post-CI trigger cleanup only).
- Root cause addressed: alpha42 allowed arbitrary observed conversation requests to mutate foreground `CEConversationContext` in both `CENetworkObserver.observeRequest:` and a separate `CEContextResolver` task-resume probe. Background/detail traffic could therefore replace visible B with unrelated A.
- Alpha44 removes both network-driven active-ID writers. `CENetworkObserver` is passive again. Current-conversation proof is now derived from currently visible UIKit evidence and requires one unique catalog-backed conversation.
- Floating Pull/Reload/Export re-check the exact visible record immediately before action. Pull and the actual manual-reload override also independently require fresh visible proof. Ambiguous/unavailable proof fails closed instead of using a cached/stale ID.
- CI passed: run `32937976994`, job `98082904535`.
- Artifacts: package id `9595516821`, digest `sha256:c084a7e6bce60d4df0a7378ae351b75a2de0669d898fd5f9a019e504c791eb99`; dylib id `9595517523`, digest `sha256:e36cfdd0571b9ee34fb629e58f066947b231602194c2a1301b17c5ab2a28c7a9`.
- Runtime/manual/real-device: **Pending**. Required stress acceptance: repeated A↔B switching plus idle/background time; Pull/Reload/Export must target the visible conversation or explicitly refuse, never a different conversation.
- Status: Candidate; not Stable/Frozen.

### Rejected `0.1.0-alpha42-project-conversation-title`

- Actions `32855687010` passed and artifacts were produced, but real-device testing on 2026-08-26 **failed**.
- User reports that after extended use both Pull Latest and Reload still cross/wrong conversations. This is authoritative runtime evidence that alpha42's recognition invariant failed despite CI/artifact success.
- The project-header conversation-title replacement also had no visible effect. That cosmetic issue is deferred until recognition is safe.
- Alpha42 is rejected and must not be treated as a baseline.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 is stacked on the earlier alpha42 recognition branch.
- Its percentage-specific CI/artifacts remain separate evidence, but the embedded alpha42 recognition dependency is now known rejected. The percentage task must re-stack/revalidate after a recognition candidate is accepted.

### Earlier alpha41 / alpha40 / alpha39

- Alpha41 was superseded pre-runtime after synthetic project-header text was found capable of feeding identity paths.
- Alpha40 compiled/produced artifacts but was not separately accepted on device before the later alpha42 lineage failed.
- Alpha39 exact-current reload contract remains architectural history, but the base lineage has known stale/current-conversation problems.

### Legacy/native tracks

- `feat/initial-ios-shell` / Draft PR #1 and `feat/0.2-native-recovery-exporter` remain legacy, not the current enhancer baseline.

## Current architecture

1. `CEBootstrap` — startup owner.
2. `CECore` / `CEConversationContext` — authoritative active conversation state and shared UI helpers.
3. `CENetworkObserver` — passive official-network observation/template/event/catalog input; **observed requests do not determine foreground conversation identity**.
4. `CEAPIClient` — sole enhancer-originated request owner.
5. `CECatalog` — conversation ID/title/project catalog.
6. `CEEnhancerUI` — host UIKit integration and action-time visible-conversation verification.
7. Features/Export/Diagnostics consume those owners.

## Current development direction

- Eliminating cross-conversation execution is the highest priority. False-negative refusal is acceptable while wrong-conversation execution is not.
- Foreground identity must be independently supported by currently visible evidence; generic official background/request traffic is not foreground authority.
- Pull/reload must fail closed at the consumer/action boundary when exact visible identity cannot be proven.
- Project-header title replacement is deferred until the identity invariant passes repeated real-device testing.
- `DEV-conversation-usage` remains isolated; do not silently merge its alpha43 state into alpha44.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change.
- No verified automated unit/UI test suite exists; CI build success is not runtime proof.
- Brand-new uncatalogued conversations or duplicate titles can intentionally produce “无法确认当前可见会话” under alpha44.
- Project chats may expose less direct visible identity than ordinary chats; alpha44 intentionally refuses rather than falling back to a stale ID.
- GitHub Actions writes run IDs back to branches; current head can differ from tested source by bookkeeping/workflow-only commits.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.
