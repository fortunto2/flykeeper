# Privacy Policy — Flykeeper

**Last updated: 14 September 2026**

## The short version

Flykeeper collects nothing. It sends nothing. It has no account, no analytics, no
advertising, and no network code of any kind.

## What the app stores

One thing, on your device only: how hungry, rested and happy your fly is, and when that was
last true. It lives in the app's own storage (`UserDefaults`) so the fly keeps living while
the app is closed. Deleting the app deletes it. It is never uploaded anywhere, because there
is nowhere for it to go.

## What the app sends

Nothing. The app contains no networking code. There is no `NSAppTransportSecurity` section in
its `Info.plist`, no server, no SDK, no crash reporter, no third-party library that phones
home. The connectome it simulates is a file inside the app; it is read from disk, not fetched.

You can check this yourself: the source is at
<https://github.com/fortunto2/flykeeper>.

## Permissions

None. Flykeeper asks for no camera, no microphone, no photos, no location, no contacts, no
notifications, no tracking.

## Children

The app is safe for any age: it collects no data, so there is nothing to collect from a child
either.

## Third-party data in the app

Flykeeper ships a copy of the FlyWire FAFB v783 connectome (Dorkenwald et al., *Nature* 2024;
Schlegel et al., *Nature* 2024), licensed CC BY 4.0, and a public-domain fly model by
Kohyzazi. These are static files bundled with the app. They contain no personal data and do
not communicate with anything.

## Changes

If this policy ever changes, the new version replaces this file in the repository above, and
its git history shows exactly what changed and when.

## Contact

Rustam Salavatov — <info@superduperai.co>
