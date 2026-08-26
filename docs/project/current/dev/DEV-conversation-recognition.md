# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` = `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged after alpha52 runtime capture.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; current branch head after alpha53 cleanup is `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not touch percentage-owned files/checkpoint.
- **Candidate uniqueness**: recognition alpha42–52 and parallel alpha43 were already allocated. `ENH-0.1.0-alpha53-refresh-path-trace` / `0.1.0-alpha53-refresh-path-trace` is unique.
- **No Frozen conflict**: product modules remain Active. Alpha53 is diagnostic-only and does not change identity ownership or production refresh semantics.

## Previous candidate — alpha52

- **Candidate**: `ENH-0.1.0-alpha52-sync-refresh-handoff` / `0.1.0-alpha52-sync-refresh-handoff`.
- **Build/test source**: `9c06219cdee1ac00b75372f1480278169b3f6e59`.
- **Actions**: run `33004675627`, job `98295074960` — success.
- **Post-CI cleanup head**: `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- **Artifacts**: package id `9620028731`; dylib id `9620029383`; extracted dylib sha256 `0b19bb2ec6d2b9a5ff26210bbd8d8945cffa77bb280b38e28ef1e0f9dc7f62d5`.
- **Validation**: Code written → CI passed → Artifact produced → Runtime/manual partially tested. Nothing Stable/Frozen.

## Authoritative alpha52 A → B → A runtime evidence — 2026-08-27

Trace `conversation-identity-585B0B11-C85D-4A19-BA16-4F55D56A320A.log`, enhancer `0.1.0-alpha52-sync-refresh-handoff`, app `1.2026.202`:

- Trace starts while A is current: `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`.
- Normal A → B navigation produced exact B `POST /backend-api/conversation/init` with body ID `6a8efab8-8898-83ec-ab3a-555b7cb9d32e`; about 120–125 ms later the host issued two exact B `/backend-api/f/conversation/prepare` requests and one exact B `GET /backend-api/conversation/<B>`.
- While B remained visible the host continued B-scoped prepare/status activity, including `POST /backend-api/conversation/<B>/async-status`.
- Normal B → A return first emitted an ID-less `conversation/init` + ID-less prepare/project-loading sequence, then exact A `conversation/init` body ID `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`; about 125 ms later it issued exact A prepare + detail GET + a second exact A prepare.
- `IDENTITY-INIT` accepted B and then A exactly, so foreground identity behavior remained correct during the genuine navigation sequence.
- This directly contrasts alpha51 failed same-current custom-route Reload, which produced only same-ID detail GETs and **zero exact `conversation/init` / exact `prepare`** while the visible page did not rebuild.
- Therefore genuine host navigation/rebuild is correlated with an internal host navigation-state transition that emits `conversation/init → prepare → detail`; a detail GET alone is insufficient.
- The trace does **not** prove that manually sending `conversation/init`/`prepare` requests would update UI. Those network calls are consequences/evidence of host navigation state, not proof of the state transition owner.
- Existing alpha52 trace captures network/menu/header structure but not enough call-site/UI-lifecycle evidence to identify a safe production host refresh entry point.

## Current candidate — alpha53 refresh-path trace

- **Candidate**: `ENH-0.1.0-alpha53-refresh-path-trace` / `0.1.0-alpha53-refresh-path-trace`.
- **Source baseline**: alpha52 post-CI head `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- **Build/test source**: `b62878928816c40cbed8c11847a3ed7ae494adde`.
- **Actions**: run `33007145536`, job `98303728684` — completed **success**; Checkout, run-id bookkeeping, Xcode check, Build and both artifact uploads passed.
- **CI bookkeeping**: `fa926ca61013292056e647f78d1d1677b608a72b`.
- **Post-CI cleanup/current branch head**: `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- **Post-CI compare**: tested source → current head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha53-refresh-path-trace`, id `9621009139`, digest `sha256:500a38652acf60b50f15f5ace41ca31e68a198cda3acaf724f1547f88bbeb6b2`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha53-refresh-path-trace-dylib`, id `9621009533`, Actions archive digest `sha256:5648a23263eb0d7fa535387a5f7fcbe2d8622142f0bdfd862515be32bb7d59a8`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, 594000 bytes, sha256 `78a38421fe04adba9774bb8e42947ea48120d2a61698359f04c31bdb6f6f86a2`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha53 implementation

1. Production Sync/Reload behavior remains alpha52; no refresh mechanism was changed.
2. Existing user-started identity trace now emits bounded `REFRESH-PATH` records only for semantically relevant host requests: exact `conversation/init`, exact `conversation/prepare`, and exact conversation-detail GET.
3. Each `REFRESH-PATH` record contains only structural evidence: method/path/exact conversation ID already allowed by the identity trace, key/root/top/presented view-controller class names, public `UINavigationController` stack count/visible controller class, and a bounded sanitized call-stack signature.
4. Call-stack entries redact raw hexadecimal addresses, exclude enhancer frames where possible, cap at eight frames, and never persist Authorization, Cookie, account IDs, raw request templates, full headers, raw request/response bodies or message content.
5. No new startup owner, identity authority, request owner, retry/timer/watchdog, `/resume`, manual init/prepare replay, private-class hard-coding, alternate ID, History/sidebar/UIKit pop-push fallback, Catalog throttling, project-header change or percentage change was added.

## Required alpha53 capture

Use one trace session:

1. start `会话识别记录` while A is visible;
2. normally switch A → B → A;
3. after returning to A, press `同步最新消息` once and wait until its final status;
4. do not perform other conversation navigation during that Sync attempt;
5. end/export the same trace.

The comparison target is `REFRESH-PATH`: genuine A→B→A navigation versus the same-A Sync/custom-route handoff. If the genuine path reveals a stable host-side caller/navigation signature absent from failed same-current refresh, that becomes evidence for the next production mechanism. If it does not, do not guess.

## Architecture retained / rejected routes

- Sole active identity owner: `CEConversationContext`; only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity.
- Generic request recency, title-only matching and arbitrary UUIDs are not identity authority.
- Current menu freezes exact ID; sidebar Rename/Export remain row-scoped.
- `CEAPIClient` remains sole enhancer-originated request owner; 429 remains terminal for the current request.
- Do not claim GET/request/openURL success as UI Sync/Reload success.
- Do not automatically repeat same-route delivery once exact same-ID request delivery is proven but UI effect is absent.
- Genuine navigation traffic is evidence of host state transition, not authorization to replay its requests manually.
- Project-header work remains paused; percentage-owned files remain untouched.

## Next exact action

Hand alpha53 to the user and obtain the single combined A → B → A → Sync trace described above. Inspect `REFRESH-PATH` structural evidence before any production refresh change. Do not implement a new refresh mechanism unless the trace identifies an evidence-backed host entry path.