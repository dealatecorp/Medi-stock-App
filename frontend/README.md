# MediStock Mobile

MediStock is an offline-first pharmacy operations app for Android and iOS. It
keeps purchases, stock, sales, reports, branches, and staff on the device and
does not require MySQL, an application server, or an internet connection.

## Features

- Built-in administrator login with a persistent signed-in session, plus local
  staff sign-in that records each successful daily check-in.
- Dashboard totals for medicines, stock value, low-stock items, and sales, plus
  low-stock alerts and recent invoices.
- Supplier profiles and purchase intake with CSV import, offline fuzzy medicine
  matching, custom medicine creation, historical purchase-rate hints, draft
  autosave, and atomic stock receipt.
- Medicine inventory with add, edit, delete, search, batch/code, barcode,
  manufacturer, manufacture and expiry dates, branch, quantity, reorder level,
  cost, selling price, Schedule H/H1 classification, dosage form, and 3/6 month
  expiry filters.
- Camera barcode scanning with manual barcode entry as a fallback.
- Branch availability for matching medicine batch/codes, including branch
  distance and quantity.
- Admin-only branch monitoring with active/inactive controls, inventory value,
  stock health, assigned staff, and today's check-in statistics.
- Admin-only staff management with add, edit, deactivate, delete, branch/role
  assignment, secure PIN access, last login, and today's attendance status.
- Billing for walk-in or named patients, optional doctor details, live stock
  checks, composition-based substitutions, repeat invoice, global and line
  discounts, payment method, refill date, and automatic stock deduction.
- Searchable invoice history with locally generated A4, A5, A6, and Thermal
  PDFs, optional UPI payment QR, preview, printing, and sharing.
- Date-filtered sales/profit, purchase/payables, GST, and expiry reports with
  offline CSV export.
- An offline support centre with system diagnostics, privacy details, and
  clearly marked future sync and messaging integrations.
- On-device low-stock notifications.
- Sample-data loading and local-data clearing for demonstrations.

## Built-in login

Use the following credentials:

- Email: `admin@gmail.com`
- Password: `12345678`

Authentication is local to the app; these credentials are intended for the
built-in demonstration workflow and are not a replacement for a production
identity service.

Administrators create staff accounts from **Admin → Staff**. A staff member then
selects **Staff** on the login screen and enters their email plus 4–8 digit PIN.
PINs are salted and hashed before storage. Staff access is rejected when either
the account or its assigned branch is inactive. Staff sessions intentionally
return to the login screen after an app restart so a new sign-in can record the
day's attendance.

## Offline storage

Medicines, suppliers, purchase drafts, invoices, invoice items, branch status,
staff accounts, attendance, and sample data are stored in an SQLite database on
the device. Admin login state is also stored locally. No MySQL instance,
backend server, or network connection is required for the core workflows.

Data is specific to each app installation and is not synchronized between
devices or branches. Clearing app data, using the in-app clear-data action, or
uninstalling the app can remove the local records, so export or share any PDFs
that need to be retained elsewhere.

## Setup

Install Flutter with a compatible Dart SDK, Android Studio and the Android SDK
for Android development. Building for iOS requires macOS with Xcode and valid
code-signing configuration.

From the `frontend` directory, install the packages and verify the toolchain:

```sh
flutter pub get
flutter doctor
```

Connect a physical device or start an emulator, then confirm that Flutter can
see it:

```sh
flutter devices
```

Camera access is requested when barcode scanning is used. Notification access
is requested at runtime where the operating system requires it. Denying camera
access still leaves manual barcode entry available.

## Run

```sh
flutter run
```

To target a particular connected device:

```sh
flutter run -d <device-id>
```

## Build

Create Android release artifacts with:

```sh
flutter build apk --release
flutter build appbundle --release
```

On macOS, create an iOS release build with:

```sh
flutter build ios --release
```

Store distribution still requires the usual Android signing or Apple signing
and provisioning setup.

## PDF and WhatsApp sharing

Invoice PDFs are generated on the device. Printing and sharing use the
operating system's print/share interfaces. Choosing **Share PDF** can send the
file to WhatsApp when WhatsApp is installed and offered by the system share
sheet, but MediStock does not send messages automatically, choose a recipient,
or confirm delivery. The user must select WhatsApp, choose the conversation,
and send the document. There is no WhatsApp Business API or server-side
delivery integration in this offline mobile app.
