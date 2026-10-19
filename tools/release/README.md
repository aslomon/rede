# Local release tools

Run `./release --help` for commands. The full operating procedure and approval boundary are in
[docs/release-process.md](../../docs/release-process.md).

- `prepare --version X --build N`: local universal build, stable signing, archive, appcast, verification.
- `verify dist/vX`: public-key signature and extracted bundle verification, including identity continuity.
- `publish dist/vX --confirm-sha256 HASH`: separately owner-approved draft upload, publication, anonymous verification.
- `verify-remote [dist/vX] --repository owner/repo --expect-tag vX`: anonymous verification of the exact tag, full feed/metadata bytes, latest pointer, and signed archive.

Signing uses the existing local Keychain account `rede`. No private key is exported.
Tests mock publication and never create a release. Test fixtures and verification evidence are retained.

## Real local Sparkle rehearsal

Run the isolated component acceptance test with pinned local Sparkle artifacts:

```sh
python3 tools/release/rehearsal.py \
  --framework /absolute/path/to/Sparkle.framework \
  --sparkle-tools /absolute/path/to/Sparkle/bin
```

The harness compiles the actual app UpdateService files with Sparkle, creates separately identified
stable-signed bundles outside Applications, and serves only a loopback feed/archive. It requires
real automatic download, staged state, ordinary quit, actual bundle replacement from synthetic
build 2 to 3, deep strict code-signature verification, matching installed designated requirement,
and a launch of the new executable. A separate downloads-disabled case must fetch no archive.
It records raw HTTP targets to verify profiling query parameters are absent. Fixtures and logs
stay in a unique ignored `.derivedData-release/` directory. No user app, permissions, hotkeys,
settings, or application bundle are replaced. This component test does not prove the full app UI
or macOS permission preservation. Keychain access remains subject to the same existing-access rule.
