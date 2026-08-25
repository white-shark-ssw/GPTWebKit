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
| `ENH-0.1.0-alpha40-conversation-recognition` | `DEV-conversation-recognition` | `0.1.0-alpha40-conversation-recognition`; Actions not run yet | `feat/conversation-recognition`; PR not created yet | Current code head `0b56a263dc9c1a00e20b4e765ffeac32d612cf40` before version-sync commit | Code written; CI not run yet | Reserved: `ChatGPTEnhancer-0.1.0-alpha40-conversation-recognition`, `...-dylib` | Runtime/manual not tested yet | Reserved |
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
