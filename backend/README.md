# MediStock offline backend

This local Dart package owns MediStock's domain models and SQLite persistence.
It is consumed by the Flutter app through a path dependency and does not start
a server, expose a network port, or require MySQL.

The embedded database runs inside the mobile app. Medicines, suppliers,
purchase drafts, completed purchase history, invoices, branch statistics,
staff accounts, salted/hashed staff PINs, daily attendance, and dashboard
aggregates remain on the device unless the user explicitly clears them.

Schema version 3 adds the offline purchasing workflow and sales metadata from
the target architecture. Draft purchases replace their line snapshot on every
save. Completing a purchase is an atomic, one-time operation that validates all
medicine mappings before increasing stock and recording the latest cost, MRP,
and expiry date. Invoice creation similarly validates and decrements stock in a
single transaction while snapshotting cost and line discounts.

Medicine matching is intentionally local: a deterministic fuzzy matcher ranks
the medicines already saved on the device. There are no cloud catalogue,
remote sync, messaging, or payment-service calls in this package.
