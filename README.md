# MediStock Mobile

MediStock is an offline-first Flutter pharmacy inventory and billing app. The
legacy website has been removed; this repository now contains only the mobile
application and its local data layer.

## Project layout

```text
frontend/  Flutter UI, mobile platform projects, controller, PDF/share, scanner
backend/   Local Dart domain and SQLite persistence package
```

`backend/` is an embedded package, not a web server. It runs inside the Flutter
application, opens no network port, and requires neither MySQL nor an internet
connection.

## Run

```sh
cd frontend
flutter pub get
flutter run
```

Use `admin@gmail.com` and `12345678` to sign in. See
[`frontend/README.md`](frontend/README.md) for the complete feature and build
notes.

## Android APK

The installable MediStock 1.0.2 APK is at
[`releases/MediStock-v1.0.2.apk`](releases/MediStock-v1.0.2.apk). It is stored
with Git LFS because it exceeds GitHub's normal Git file-size limit. After
cloning, run `git lfs pull` to download the full APK.
