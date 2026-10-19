# Local signed release process

The updater downloads its feed from
`https://github.com/aslomon/rede/releases/latest/download/appcast.xml`.
The repository must be public. Each complete release contains a universal signed ZIP,
a cumulative `appcast.xml`, and `release.json`; all three assets upload to a draft before it
becomes public and latest. Pages is not the release feed.

The installed 1.0 (build 1) still points to the unavailable Pages feed. It needs one manual
installation of the first corrected build. There is no Pages compatibility feed in this scope.
A fresh unnotarized installation may require **Open Anyway** in Privacy & Security.

## Signing identities

Code signing uses the existing **rede Local Dev** certificate. The release verifier requires
its designated requirement to equal the previous release's requirement, preserving the identity
used by Accessibility and Microphone permissions. Never recreate or replace this certificate
for a routine release. Preserve the trusted local `llama-server` helper and its companion dylibs.
The supplied input checksum detects staging changes; because it is calculated from that local file,
it is not an independent upstream provenance pin. The release records hashes and architectures of
every bundled helper/dylib after signing and verifies that inventory after extraction. Those hashes
are review evidence, not an assertion that helper bytes equal an earlier release's signed bytes.
The app, helper, and mandatory Intel dependencies must be universal. The existing Metal backend
alone may remain arm64-only, with links confined to Helpers and no x86_64 mandatory dependency
on it. This preserves the trusted runtime; it makes no Intel Metal acceleration claim.

Sparkle signing uses the existing login Keychain entry for service
`https://sparkle-project.org`, account **rede**. The pinned public key is in Info.plist.
Before any key access, the tool rejects symlinked or SHA-256-mismatched `sign_update` and
`generate_keys` executables against the pinned universal Sparkle 2.9.3 artifact identities.
It compares the public key before signing and fails on a mismatch. It invokes:

```sh
generate_keys --account rede -p
sign_update --account rede /absolute/path/to/rede-version.zip
```

`-p` reads only the public key. Do not generate, rotate, export, copy, or provision a private key
for this process. No CI signing secret is required. If macOS requests new Keychain access,
stop and let the owner decide; do not change access controls.

## Prepare and verify

Use a reviewed, committed, clean checkout with an `origin` that identifies this repository.
Xcode 26 or newer, XcodeGen, Python 3, GitHub CLI authentication, the stable certificate,
the existing Sparkle key, and pinned Sparkle 2.9.3 tools are required. The source feed must
match the repository derived from `origin`. The previous installed app supplies the signing
requirement for the first release; later releases use published metadata and appcast history.

Write short German HTML notes to `tools/release/notes/<version>.de.html`, then run:

```sh
tools/release/release prepare --version 1.1.0 --build 2 \
  --previous-app /Applications/rede.app \
  --sparkle-tools /absolute/path/to/Sparkle/bin
tools/release/release verify dist/v1.1.0 --previous-app /Applications/rede.app
```

The first corrected artifact target is 1.1.0 (build 2), recorded persistently in `RedeMac/project.yml`.
That engineering target does not authorize publication. CLI version/build and the `v<version>` tag
must match this source of truth; future local builds use it too. The build must exceed
both the installed build 1 and every published build. `prepare` passes explicit version/build
overrides to the universal Release build, retains the stable helper and signing path, archives
with `ditto`, signs through Keychain account `rede`, and runs verification. It reads non-empty UTF-8 German notes only from tracked files inside `tools/release/notes/`.
The clean source commit is captured before building; HEAD and cleanliness are checked again after
the build, and metadata retains that captured commit. It never overwrites an existing
`dist/v<version>` directory. A failure leaves local evidence for inspection. The fixed release archive policy allows a positive
integer length up to 2 GiB. Public verification checks this before opening the archive download
and counts streamed bytes against both the expected length and the absolute limit; missing or
false Content-Length headers do not relax those bounds.

`dist/v<version>/` contains the archive, appcast, metadata, and build log. Verification checks the
archive hash and length, public-key Ed25519 signature, feed enclosure, bundle version/build,
minimum OS, profiling defaults, universal architectures, SDK, deep strict code signature, and
unchanged designated requirement. Rehearsal markers and flags are rejected. Delta updates are
not generated. The cumulative appcast preserves prior items and their German release notes. Verification requires
every previous build/URL/signature/length tuple to survive, exactly one current build item, and
non-empty current release notes.

## Owner approval and publication

Review the concrete archive and `release.json`, including its SHA-256, before owner approval.
Only after that approval, run the exact hash-confirmed command:

```sh
tools/release/release publish dist/v1.1.0 --confirm-sha256 EXACT_VERIFIED_ZIP_SHA256
```

The command verifies again and confirms that GitHub already resolves the exact reviewed source
commit. An existing version tag must resolve to that commit too. The separately approved source
push belongs to the integration owner; this tool never pushes, commits, or replaces a tag.
It snapshots all three asset hashes, verifies them again immediately before upload, and uploads
them as a draft. Before publication it rechecks local hashes and the draft's exact asset names,
completed upload states, sizes, and SHA-256 digests when supplied by GitHub. A mismatch or failed
upload leaves the draft unpublished. Only then does it publish that release as latest.
Publication also authorizes GitHub to create the version tag at the approved source commit. No feed is advertised while its archive is private.
A public release mutation cannot be undone merely by local Trash recovery; approval applies to
the specific verified archive hash. The updater implementation task does not run this command.

After publication, the tool anonymously fetches the tag-specific feed and metadata, requires their
complete bytes to match the local reviewed files, and requires the latest pointer to serve those
same assets. It then checks the exact archive's hash/length and public-key signature. The release
workflow passes the published event's tag, so a stale latest pointer cannot pass on an older release.
If a public post-check fails, preserve the evidence and report the failed check. The owner must
decide whether to withdraw or repair the public release; this tool makes no automatic rollback,
asset replacement, or retry over an existing release/draft. Run that independent read-only
check again with:

```sh
tools/release/release verify-remote --repository aslomon/rede --expect-tag v1.1.0
```

The GitHub release workflow only performs this anonymous check after publication. It does not
build, sign, export keys, create releases, or push an obsolete `gh-pages` feed.

## Local acceptance and recovery

`python3 -m unittest discover -s tools/release -p 'test_*.py'` exercises metadata and draft ordering
without external writes. `scripts/test-build-cleanup.sh` tests scoped reversible cleanup.
The local Sparkle rehearsal uses a separate bundle/defaults domain, stable signing, and a loopback
feed. Its test-only compile marker is rejected by production release verification. It must prove
an actual older-to-newer Sparkle replacement; HTTP availability alone is insufficient.

Local evidence, failed builds, and fixtures are retained. The build's known cleanup targets go to
macOS Trash through `/usr/bin/trash -s -v`; non-macOS test paths move to a retained recycle folder.
Never empty Trash as part of a release. If preparation fails, inspect the retained evidence and
choose a new output/version directory after resolving the cause.
