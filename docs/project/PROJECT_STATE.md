# Project State

_Last updated: 2026-08-25._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified` from repository evidence alone.
- The default branch `main` is **not** proof of the latest product behavior; before governance installation it contained only the initial README and placeholder file.
- The newest repository development track is `feat/chatgpt-enhancer-v0.1`, which contains `ChatGPTEnhancer` and the latest build candidate.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha39-reload-stability`

- Branch head: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` (CI run-id bookkeeping commit).
- Build source head for Actions run `32841238704`: `70905cc5d038d41a900e626f0c6467c5d0573ef9`.
- Functional alpha39 reload change: `8e520cba370870173a5ef08392636e1ca8036308` (`fix: make exact-current conversation reload retry-safe`).
- CI: passed.
- Artifacts produced: `ChatGPTEnhancer-0.1.0-alpha39-reload-stability` and `ChatGPTEnhancer-0.1.0-alpha39-reload-stability-dylib`.
- Runtime/manual/real-device result for **alpha39 specifically**: `Unknown / Unverified` in repository evidence; do not describe alpha39 runtime issues as solved merely because CI/artifacts succeeded.
- PR: none recorded for this branch in the scanned repository state.

### Legacy/native app branches

- `feat/initial-ios-shell` head `48c42c706def626c5ab363778fb1f4013767c79c`; open Draft PR #1 targets `main` and describes the earlier WKWebView shell.
- `feat/0.2-native-recovery-exporter` head `f1a6fac30d3b4ba8dd790679ef666debbcfc5fd5`; contains the later native utility/Markdown-export app line and unsigned IPA workflow.
- These are repository candidates/history, not the current enhancer baseline. Do not resume or modify either merely because the branch exists; development routing still requires a selected Active checkpoint.

## Current architecture

The current enhancer is a host-app injected dylib with separated state ownership:

1. `CEBootstrap` is the single constructor/startup entry.
2. `CECore` owns generic helpers and active conversation context.
3. `CENetworkObserver` observes official networking and keeps sensitive request material only in memory.
4. `CEAPIClient` is the single enhancer-originated request path.
5. `CECatalog` owns conversation catalog resolution.
6. `CEEnhancerUI` owns host UI integration.
7. Export, feature and diagnostics modules consume those owners rather than establishing parallel authorities.

## Current development direction

- Treat `ChatGPTEnhancer` as the current active product track unless a future explicitly routed development task says otherwise.
- Preserve the old native/WebView code as a separate legacy track. Do not mix its UI/recovery/upload architecture into enhancer work without explicit evidence and task scope.
- Current alpha39 direction keeps manual reload on the exact current conversation and verifies delivery through the host app's own detail/resume request behavior.

## Known issues / constraints

- ChatGPT private backend routes and host-app runtime surfaces are undocumented and can change.
- The repository currently has no verified automated unit/UI tests or dedicated lint/static-analysis suite; CI build success is not runtime validation.
- Enhancer version identity is duplicated across `CECore.mm`, `build.sh`, and `build-enhancer.yml`; candidate changes must keep them synchronized.
- The enhancer branch still contains older `GPTWebKit` native app source and a root README describing the earlier 0.3 utility, so source-track identity must be resolved before development work.
- Existing Draft PR #1 belongs to the legacy WebView shell; do not treat it as the enhancer PR.
- GitHub Actions commits run IDs back to feature branches, so branch head may be a CI bookkeeping commit rather than the last functional code change.

## Evidence rule

Always distinguish source written, checks/CI passed, artifact produced, runtime/manual tested, and Stable/Frozen acceptance.
