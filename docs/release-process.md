# Release Process (Sparkle Updates)

How a rede release is built, signed, published, and picked up by the in-app updater.
The update feed lives on this fork (`aslomon/rede`): GitHub Releases hold the signed
zips, GitHub Pages (branch `gh-pages`) serves `appcast.xml`, and the app checks it daily
(`SUFeedURL` in `Resources/Info.plist`).

## One-time setup

1. **EdDSA keypair** (already done on the primary dev machine):
   ```bash
   ./sparkle-tools/bin/generate_keys        # writes the private key into the login Keychain
   ./sparkle-tools/bin/generate_keys -p     # prints the public key for Info.plist (SUPublicEDKey)
   ```
   - The PRIVATE key never leaves the Keychain unencrypted and is NEVER committed.
   - Backup: `generate_keys -x sparkle_private_key` to an encrypted disk/password manager,
     then delete the plain file. Losing this key strands users on old versions.
   - CI: export once via `generate_keys -x -` and store as the `SPARKLE_PRIVATE_KEY` repo secret.
2. **GitHub Pages**: enable Pages for the `gh-pages` branch (Settings → Pages → Deploy from
   branch → `gh-pages` / root). The feed URL is
   `https://aslomon.github.io/rede/appcast.xml`.
3. **Sparkle CLI tools**: download the release matching the pinned version in `project.yml`:
   ```bash
   curl -LO https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz
   mkdir sparkle-tools && tar -xJf Sparkle-2.9.3.tar.xz -C sparkle-tools
   ```

## Versioning rules

- `CURRENT_PROJECT_VERSION` (build number) must increase **strictly monotonically** — Sparkle
  compares `sparkle:version`, i.e. the build number.
- `MARKETING_VERSION` is the user-facing string; the git tag is `v$(MARKETING_VERSION)`.
- Both live in `RedeMac/project.yml`.

## Cutting a release (local path — primary until Developer ID exists)

CI artifacts are ad-hoc signed until a Developer ID secret exists, which breaks TCC grants on
every update. Until Phase 3 (notarization) lands, build releases LOCALLY with the stable dev
cert ("rede Local Dev", installed via `scripts/create-dev-cert.sh`):

```bash
# 1. Bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in RedeMac/project.yml; commit.
# 2. Build the helper + the universal release app:
./scripts/build-llamacpp-helper.sh
HELPER="$PWD/.derivedData-llamacpp-helper/output/llama-server"
./build.sh --release --llamacpp-helper="$HELPER" --llamacpp-helper-sha256="$(shasum -a 256 "$HELPER" | awk '{print $1}')"

# 3. Zip (ditto preserves signatures/symlinks; plain zip can corrupt the bundle):
ditto -c -k --sequesterRsrc --keepParent rede.app rede-<version>.zip

# 4. EdDSA-sign the archive (key from Keychain):
./sparkle-tools/bin/sign_update rede-<version>.zip
#    → sparkle:edSignature="…" length="…"

# 5. Tag + release on the fork:
git tag v<version> && git push fork v<version>
gh release create v<version> --repo aslomon/rede --title "rede v<version>" \
  --notes "<German release notes from CHANGELOG>" rede-<version>.zip

# 6. Update appcast.xml on gh-pages: add a new <item> (template below), commit, push.
```

Appcast item template:

```xml
<item>
  <title>Version <version></title>
  <pubDate><RFC 2822 date></pubDate>
  <sparkle:version><CURRENT_PROJECT_VERSION></sparkle:version>
  <sparkle:shortVersionString><MARKETING_VERSION></sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <description><![CDATA[ <German release notes, short HTML> ]]></description>
  <enclosure
    url="https://github.com/aslomon/rede/releases/download/v<version>/rede-<version>.zip"
    sparkle:edSignature="<from sign_update>"
    length="<from sign_update>"
    type="application/octet-stream"/>
</item>
```

## Cutting a release (CI path — scaffolding)

`.github/workflows/release.yml` runs on tag push `v*`: helper build → universal release build →
zip → `sign_update` (secret `SPARKLE_PRIVATE_KEY`) → draft GitHub release → appcast push to
`gh-pages`. Validate the first run end-to-end before trusting it; flags of the Sparkle CLI tools
should be double-checked against the pinned Sparkle version.

## Verifying an update end-to-end (manual test)

1. Build + install the CURRENT version into `/Applications` (`./build.sh --install`).
2. Bump versions, build the NEW version, zip + `sign_update` it.
3. Serve a local appcast: put `appcast.xml` + zip into a folder,
   `python3 -m http.server 8000`, point `SUFeedURL` at
   `http://localhost:8000/appcast.xml` for the INSTALLED build (temporary test build), or use
   `defaults write app.rede.mac SUFeedURL http://localhost:8000/appcast.xml`.
4. Einstellungen → System → Updates → "Jetzt nach Updates suchen": Sparkle must show the new
   version, install it, and relaunch the app.
5. Remove the `defaults` override afterwards: `defaults delete app.rede.mac SUFeedURL`.

## Phase 3 follow-ups (needs Apple Developer account)

- Developer ID Application certificate; sign helper with hardened runtime +
  `com.apple.security.cs.disable-library-validation`; sign Sparkle components hardened.
- `notarytool submit` + `stapler staple`; CI secrets for an App Store Connect API key.
- After that: CI becomes the primary release path; TCC grants survive updates for end users.

## Honesty checklist per release

- German release notes match what actually shipped (CHANGELOG section).
- Privacy docs still accurate (no new data flows).
- `./test.sh` green, `./build.sh --release` universal-verified before tagging.
