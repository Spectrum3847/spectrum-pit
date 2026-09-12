# Running Spectrum Pit for your own team

The builds we publish are wired to Spectrum 3847's Firebase project. You
cannot repoint them from Settings, because there is no URL to change: the
backend is Firebase, and its identifiers are compiled into the binary. To run
this app on your own data you fork the repository, put your own Firebase
project into it, and build it yourself.

Budget an afternoon, and read the next section first.

## What the backend is

Two Firebase projects and one small HTTP service, no server we wrote.

**Your app project** holds Firestore: inventory items, packing records,
borrowed tools, map locations and diagrams, and the pit shift schedule, plus
`userProfiles` which is where roles live. `firestore.rules` in this repository
is the only authorization there is. Everything else is a client talking
straight to Firestore.

**A central project** owns the roster. Sign-in goes Google, then a session on
the central project, then a Cloud Function called `getCustomToken` that checks
the person is an approved member and that your app is registered, and mints a
custom token the app swaps for a session on the app project. Spectrum uses its
SpectrumTasks project for this so one roster covers several team apps.

**A photo service** holds the image bytes. Packing photos and pit map
diagrams do not go into Firestore; the app uploads them over HTTP and stores
only the returned key. Ours is a Cloudflare Worker writing to an R2 bucket,
because Firebase Cloud Storage needs the Blaze plan and our app project is on
the free Spark plan. Section 7 has the contract.

The Blaze plan is the one unavoidable cost. Cloud Functions do not run on
Spark, so your **central** project has to be on Blaze even though a team-sized
load stays inside the free monthly allowance. Your app project can stay on
Spark, like ours.

## Before you start

- A Google account, and a card for the Blaze plan on the central project.
- The Flutter SDK, at the version this release pins. `pubspec.yaml` has the
  constraint and [flutter.dev](https://docs.flutter.dev/get-started/install)
  has the installer.
- The Firebase CLI (`npm install -g firebase-tools`) and the FlutterFire CLI
  (`dart pub global activate flutterfire_cli`).
- A Cloudflare account if you want photos. The free tier covers this.

## 1. Fork this repository

Fork it, clone your fork, and run `flutter pub get`. That is the only
repository you need; everything Spectrum-specific is either a build flag or a
config file you regenerate.

## 2. Create your Firebase projects

In the [Firebase console](https://console.firebase.google.com/), create two
projects. This guide calls them `yourteam-pit` and `yourteam-central`.

On **yourteam-pit**:

- Build > Firestore Database > create a database, production mode, in the
  region closest to your events.
- Build > Authentication > Sign-in method > enable Google.

On **yourteam-central**: the same two, plus upgrade to the Blaze plan so you
can deploy a function.

## 3. Generate the app's Firebase config

```
flutterfire configure --project=yourteam-pit
```

Pick the platforms you build for. That rewrites `lib/firebase_options.dart`
and drops `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist` into place. On Android, register your
signing key's SHA-1 with the Firebase Android app afterwards, or Google
sign-in returns a token the project refuses.

## 4. Deploy the rules

```
firebase use yourteam-pit
firebase deploy --only firestore:rules,firestore:indexes
```

Do this before anyone signs in. Firestore's defaults either lock everyone out
or leave your inventory world-writable.

## 5. Point the central handshake at your project

The central project id is a build define, so this is one flag you will pass in
step 8:

```
--dart-define=SPECTRUM_CENTRAL_PROJECT_ID=yourteam-central
```

The callable endpoint follows it automatically, resolving to
`https://us-central1-yourteam-central.cloudfunctions.net`. If you deploy the
function outside `us-central1` or behind a custom domain, override that too
with `--dart-define=SPECTRUM_CENTRAL_FUNCTIONS_BASE_URL=...`. It has to be
https either way, since that URL carries a bearer token.

One file still needs editing by hand: replace the values in
`lib/firebase_options_central.dart` with your central project's **web app**
config, from the Firebase console under Project settings > Your apps. These
are public client identifiers, not secrets.

## 6. Write the `getCustomToken` function

This is the one piece of backend code you have to supply. Ours lives in
another team app and is not published, so here is the contract the client
expects, and an implementation that satisfies it.

The client calls a v1 callable named `getCustomToken` in `us-central1` on your
central project, with the caller's central ID token as the bearer and a body
of `{"data": {"targetApp": "<your app key>"}}`. It expects back:

```json
{"result": {
  "customToken": "...",
  "profile": {"displayName": "...", "email": "...", "role": "...",
              "photoURL": "...", "slackId": "..."}
}}
```

`profile` is optional and so is every field in it. Two error codes carry
meaning: `permission-denied` means this person is not approved, and
`not-found` means the app is not registered. The sign-in screen turns both
into a readable message; anything else reads as a network or configuration
failure.

In `functions/index.js` on your central project:

```js
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

exports.getCustomToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  const targetApp = data && data.targetApp;
  if (
    typeof targetApp !== "string" ||
    targetApp.length === 0 ||
    targetApp.includes("/")
  ) {
    throw new functions.https.HttpsError("invalid-argument", "targetApp required.");
  }

  const db = admin.firestore();

  const app = await db.doc(`apps/${targetApp}`).get();
  if (!app.exists || app.get("approved") !== true) {
    throw new functions.https.HttpsError("not-found", "App not registered.");
  }

  const uid = context.auth.uid;
  const user = await db.doc(`users/${uid}`).get();
  if (!user.exists || user.get("approved") !== true) {
    throw new functions.https.HttpsError("permission-denied", "Not approved.");
  }

  return {
    customToken: await admin.auth().createCustomToken(uid),
    profile: {
      displayName: user.get("displayName") || context.auth.token.name || null,
      email: user.get("email") || context.auth.token.email || null,
      photoURL: user.get("photoURL") || context.auth.token.picture || null,
    },
  };
});
```

Deploy it, then create the two documents it reads, by hand in the console:

- `apps/yourapp` with `approved: true`
- `users/<your central uid>` with `approved: true` and your `displayName`

Your central uid appears under Authentication > Users after you sign in to the
central project once, which happens the first time you try to sign in to the
app. Expect the first attempt to fail with "Account not approved", then add
the document, then try again. Every teammate needs a `users/<uid>` document
before they can get in, and that is the whole membership gate: no document, no
access.

The custom token is minted for the uid the central project knows, so
`userProfiles/{uid}` on the app project and `users/{uid}` on the central
project line up.

## 7. Stand up a photo service

Without one, packing photos and map diagrams fail. Everything else works.

The one we run ships in this repository at `scripts/photo-worker/`. It is a
Cloudflare Worker over an R2 bucket, and both are free at a team's volume.

Create the bucket in the Cloudflare dashboard, then edit
`scripts/photo-worker/wrangler.jsonc`: put your own `account_id` in place of
the placeholder, set `bucket_name` to your bucket, set `FIREBASE_PROJECT` to
your app project, and replace `ALLOWED_ORIGINS` with the origins you serve the
web build from (mobile and desktop send no `Origin`, so they need no entry).

```
cd scripts/photo-worker
pnpm dlx wrangler@latest deploy
```

Give the bucket a lifecycle rule expiring objects after 90 days. That plus the
Worker's 2 MB per-image ceiling is what stops the bucket drifting past R2's
free 10 GB, since R2 bills past it rather than stopping. The app downscales
before uploading, so real photos land nearer 300 KB.

There is no API key anywhere in this. A request carries the caller's own
Firebase ID token, and the Worker re-presents that same token to your app
project's Firestore REST API to read `userProfiles/<uid>`. Firestore verifies
the signature, so a forged token fails there and the Worker never has to
verify one itself. Members with `pit`, `admin`, or `developer` are allowed
through.

Finally, point the app at your deployment. The base URL is a constant in
`lib/src/services/photo_service.dart`:

```dart
static const String _defaultBaseUrl = 'https://your-worker.workers.dev';
```

## 8. Build

The app key is a build-time value with no default. A build without it refuses
to sign in and says so, which is deliberate.

```
flutter run \
  --dart-define=SPECTRUM_APP_KEY=yourapp \
  --dart-define=SPECTRUM_CENTRAL_PROJECT_ID=yourteam-central
```

Use the same app-key string you wrote into `apps/{key}`. Pass both defines on
every build, for every platform, or the binary talks to Spectrum's platform
and refuses your team.

Linux desktop has no FlutterFire, so it signs in through a loopback OAuth flow
and needs a Google OAuth client of type "Desktop app" from your Google Cloud
console:

```
flutter build linux \
  --dart-define=SPECTRUM_APP_KEY=yourapp \
  --dart-define=SPECTRUM_CENTRAL_PROJECT_ID=yourteam-central \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID=...apps.googleusercontent.com \
  --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=...
```

Desktop OAuth client secrets are not secret in the usual sense; Google's own
docs say a native app cannot keep one. Without these two the Linux build still
runs, local-only.

## 9. Make yourself an admin

A first sign-in creates `userProfiles/{uid}` with the `pit` role, which does
not include the Users tab. So nobody can promote anybody and you are stuck.

Break the loop in the Firebase console: open `userProfiles/{your uid}` on the
app project and change `roles` to `["admin"]`. From then on the Users tab
handles everyone else.

## What you do not get

- Our scheduled jobs (usage reports and the rest). They are separate Node
  services in the private repository. The app works without them.
- Our nightly builds and AltStore sources. The desktop update check is worse
  than missing: `_defaultRepositories` in
  `lib/src/services/desktop_update_service.dart` is hard-coded to
  `Spectrum3847/spectrum-pit`, so your fork will offer your team our builds
  and replace itself with one. Change that constant, or turn the check off in
  Settings, before you hand a desktop build to anyone.

## What you can also run

- **The MCP server**, which lets an AI agent read the database, is open source
  at [Project516/spectrum-mcp](https://github.com/Project516/spectrum-mcp). It
  holds no service account and acts as the signed-in user, so your
  `firestore.rules` governs it the same way it governs the app.
- **GitHub Actions** can build your fork for you, which is the only practical
  way to get an iOS or Windows build without owning a Mac or a Windows box.
  `.github/workflows/nightly.yml` comes with the fork and already builds
  Android, iOS, desktop, and web, and a public repository gets free minutes.
  Two edits before it works for you: the `--dart-define=SPECTRUM_APP_KEY=`
  lines carry our app key as a literal, so change every one of them, and the
  `sync` job pulls from our repository, so delete it. The Android job wants
  your `google-services.json`, base64 encoded, in the fork's own
  `GOOGLE_SERVICES_JSON` Actions secret.

## Keeping up with releases

Your fork will drift. Each of our releases lands here as one squashed commit,
and your own changes sit in a handful of files (`firebase_options.dart`,
`firebase_options_central.dart`, `photo_service.dart`), so
rebasing onto a new release is usually clean. Watch this repository's releases
and pull when you want a newer version. Nothing is automatic.

## License

This mirror is [AGPL-3.0](../LICENSE). Running a modified copy for your own
team is fine. If you run one as a service other people use, or hand out
modified builds, you owe them the source under the same license.

## If you get stuck

Open an issue on this repository. Say which step you are on and paste the
error code the sign-in screen shows; it names the failure kind, which is
usually enough to tell a rules problem from a central-handshake one.
