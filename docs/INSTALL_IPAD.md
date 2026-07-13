# Installing LifeTap 2 on your iPad

LifeTap 2 is a Flutter app. Getting a Flutter app onto an iPad is the one genuinely
awkward part of the Apple ecosystem: **building and signing an iOS app requires a Mac
with Xcode.** There is no way around that for a native install — Apple only lets a Mac
produce a signed `.app`/`.ipa`. Below are the realistic paths, easiest first. Pick the
one that matches what hardware and accounts you have.

Whatever path you choose, you never touch the App Store review process — this is a
personal/side-loaded install.

---

## Path A — You have a Mac (recommended, free)

This is the simplest reliable route. A **free** Apple ID works; you don't need the
$99/year Apple Developer Program for personal use. The only catch: apps signed with a
free Apple ID **expire after 7 days** and must be re-installed (re-run the command). A
paid account extends that to 1 year.

1. **Install the toolchain on the Mac** (one time):
   - Install Xcode from the Mac App Store, then run it once and accept the license.
   - `sudo xcodebuild -runFirstLaunch`
   - Install Flutter: https://docs.flutter.dev/get-started/install/macos — or `brew install --cask flutter`.
   - `flutter doctor` and fix anything it flags for iOS (it will prompt to install CocoaPods).

2. **Open the project and set a signing team** (one time):
   - Copy this repo to the Mac.
   - `cd lifetap && flutter pub get`
   - `open ios/Runner.xcworkspace`
   - In Xcode: select the **Runner** target → **Signing & Capabilities** → check
     *Automatically manage signing* → set **Team** to your Apple ID (add it under
     Xcode → Settings → Accounts if it's not listed).
   - The bundle identifier is `com.hlyons.lifetap`. If Xcode says it's taken, change it
     to something unique like `com.<yourname>.lifetap` — it only matters that it's unique to you.

3. **Plug in the iPad and install:**
   - Connect the iPad by cable, unlock it, and tap **Trust This Computer**.
   - `flutter devices` — confirm the iPad shows up.
   - `flutter run --release -d <ipad-device-id>`
   - First launch will be blocked by iOS. On the iPad go to **Settings → General → VPN &
     Device Management → Developer App**, tap your Apple ID, and **Trust** it. Re-open the app.

4. **When it expires (free account, ~7 days):** re-run `flutter run --release`. That's it.

> Once the app is installed you can unplug the iPad and use it normally until it expires.

---

## Path B — No Mac, but willing to use a cloud build (free tier)

You can build the iOS app on a hosted Mac without owning one. **Codemagic** has a free
tier with real macOS build machines and is the least painful for Flutter.

1. Push this repo to GitHub/GitLab (see "Getting the code somewhere" below).
2. Sign up at https://codemagic.io and connect the repo.
3. Codemagic can build an iOS app. **The signing reality still applies** — to get an
   installable build you need Apple signing credentials:
   - **Cleanest:** enroll in the Apple Developer Program ($99/year), then use Codemagic's
     TestFlight integration. You install via the **TestFlight** app on the iPad — no cable,
     no 7-day expiry, updates over the air. This is the nicest long-term setup if you're
     willing to pay the $99.
   - **Free-account option:** Codemagic can produce an `.ipa` signed with a free Apple ID's
     development certificate, which you then sideload with **Apple Configurator** (Path C) —
     same 7-day expiry as Path A.

TestFlight (paid) is the only route that gives you cable-free, non-expiring installs.

---

## Path C — Sideload a prebuilt .ipa with Apple Configurator / third-party tools

If someone hands you a signed `.ipa` (built via Path A or B), you can install it onto the
iPad from a Mac using **Apple Configurator** (free, Mac App Store) or from Windows/Mac using
a tool like **Sideloadly** or **AltStore**. These still rely on a signing certificate
underneath (free = 7-day expiry, paid = 1 year). Configurator/AltStore just handle the
"copy it onto the device" step without Xcode.

---

## Path D — No Mac at all, want it *today*: run it as a web app (PWA)

LifeTap 2 is a Flutter app and its multi-touch works through the browser's Pointer Events,
so it runs well in Safari on the iPad and can be "installed" to the home screen as a
Progressive Web App — **no Mac, no Apple account, no expiry.** It won't be a true native
app (it runs in a fullscreen Safari shell), but for a life counter that is usually fine.

**This is the chosen path (you don't have a Mac).** It is wired up in this repo:

1. `.gitlab-ci.yml` has a `pages` job that runs `flutter build web` in the Flutter
   container and publishes the result as a **GitLab Pages** site on every push to the
   default branch — served at `https://<namespace>.gitlab.io/lifetap/`.
2. The web target and an iPad-friendly PWA manifest (fullscreen `standalone`, landscape,
   apple-touch-icon) are added to the project.
3. On the iPad, open that URL in **Safari → Share → Add to Home Screen**. It launches
   fullscreen like a native app, works offline after first load, and **never expires**.

The only remaining step is pushing this repo to a GitLab project so Pages can build it;
once pushed, the URL is automatic. No Mac, no Apple account, no cable.

---

## Getting the code somewhere (for Paths B and D)

The repo is currently local-only (no remote). To use a cloud build or host the web version
it needs to be on GitHub or GitLab. Tell me which and I'll push it (it's committed and ready).

---

## Quick recommendation

- **Have a Mac?** → Path A. Ten minutes, free.
- **No Mac, want native + willing to pay $99/yr?** → Path B with TestFlight (best experience).
- **No Mac, want it now for free?** → Path D (PWA). Ask me to add the web build.
