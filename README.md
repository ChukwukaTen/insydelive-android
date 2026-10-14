# InsydeLive Android app

The InsydeLive Android app: a Capacitor 8 shell with the InsydeLive web app's files built in (`www/`),
connected to the PRODUCTION Supabase project.

- App ID: `com.insydelive.app` (permanent)
- Web app version inside: see `package.json` → `version`
- Every change pushed to `main` builds a TEST app on GitHub (Actions → "Build Android test app" → Artifacts).
- `android/app/insydelive-test.keystore` is a TEST key only (password `android`), so test builds install
  over each other. The real Play Store release key is set up separately and is never stored here.

Updating the web app inside: replace `www/` with the latest production build (without `netlify.toml` and
`_redirects`), bump `version` in `package.json`, and push.

## Play Store version
When the two GitHub Secrets `ANDROID_UPLOAD_KEYSTORE_B64` and `ANDROID_UPLOAD_KEY_PASSWORD` are set, every build also makes
`InsydeLive-STORE-<version>-code<N>.aab` (signed with the InsydeLive upload key) for uploading to Google Play Console.
The key itself is never stored in this repository. The version code is the build number, so it always goes up.
