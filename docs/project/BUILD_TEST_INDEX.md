# Build / Test / Release Index

This file is the durable index for testable identities and evidence.

## Current identity scheme

### Current ChatGPTEnhancer track

- Product version is the alpha candidate string in `CEVersion` (`ChatGPTEnhancer/Sources/Core/CECore.mm`).
- `ChatGPTEnhancer/build.sh` ZIP name and `.github/workflows/build-enhancer.yml` artifact names must match that candidate string.
- GitHub Actions run ID is build evidence and is recorded in `.github/latest-enhancer-run-id`; it is not a substitute for the product candidate name.
- New parallel Active development tasks must allocate different exact candidate/artifact identities before producing testable artifacts.

### Legacy native app track

- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` come from `GPTWebKit.xcodeproj/project.pbxproj`.
- Legacy IPA workflow currently uses an explicit artifact candidate name independent of the Xcode build number. Treat this as a separate identity namespace from enhancer candidates.

## Candidate table

| Candidate | Work ID | Version / Build / Tag | Branch / PR | Commit | Validation | Artifact | Runtime result | Status |
|---|---|---|---|---|---|---|---|---|
| `ENH-0.1.0-alpha41-project-conversation-title` | `DEV-conversation-recognition` | `0.1.0-alpha41-project-conversation-title`; Actions pending | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Reserved before code/build; pre-change branch head `5157425c3b3926ec8150486730301c7d285f24e9` | Requirement/evidence recorded; code/CI/artifact pending | Pending | Pending | Reserved candidate |
| `ENH-0.1.0-alpha40-conversation-recognition` | `DEV-conversation-recognition` | `0.1.0-alpha40-conversation-recognition`; Actions `32850463066` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test head `a7f1aba4848899ec7e5b5cdfd711b584a45d4bdd`; CI bookkeeping `ab5d8d4a5caddfc3dd3fdc88acc065b0036aa8d1`; post-CI branch head `5157425c3b3926ec8150486730301c7d285f24e9` | Code written; CI passed; Artifact produced | `ChatGPTEnhancer-0.1.0-alpha40-conversation-recognition` digest `sha256:776527c8dfa199ddfa2085a02e33dd02c49d4003a8ed170bedc2601411565433`; `...-dylib` digest `sha256:88e734bc5bc0920e45124f02af13ece6e58b2d779eca202a131e45f71dab6292` | Runtime/manual/real-device test pending; user has not yet reported the alpha40 A→B acceptance result | Candidate |
| `ENH-0.1.0-alpha39-reload-stability` | Pre-governance / unassigned | `0.1.0-alpha39-reload-stability`; Actions `32841238704` | `feat/chatgpt-enhancer-v0.1`; no PR recorded | Build head `70905cc5d038d41a900e626f0c6467c5d0573ef9`; branch head `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` | Code written; CI passed; Artifact produced | `ChatGPTEnhancer-0.1.0-alpha39-reload-stability`, `...-dylib`; artifact digests recorded by GitHub Actions | `Unknown / Unverified` for alpha39 specifically | Candidate |

## Historical / non-current identities

- Legacy native app Xcode version on scanned branch: `MARKETING_VERSION=0.3.0`, `CURRENT_PROJECT_VERSION=2`.
- Legacy IPA workflow artifact string: `ChatGPT-MD-0.3.0-alpha2`.
- Draft PR #1 (`feat/initial-ios-shell`) is the older WebView shell and has no authority over the current enhancer candidate identity.

## Uniqueness rule

Different Active tasks must not reuse the same exact candidate identity, build number, version/build tuple, release tag, artifact name or candidate ID.

Once allocated, an Active candidate identity is reserved until explicitly completed/released and documented.

## Evidence labels

- Code written
- Static/local checks passed
- CI passed
- Artifact produced
- Runtime/manual/real-device tested
- Stable / frozen
