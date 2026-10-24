# Phase 1 — Repository Audit and Implementation Plan

**Source repository:** https://github.com/Dinesh-Sowndar/flutter_billing_app  
**Audited commit:** `ff62530` (2026 repository snapshot)  
**Audit date:** 2026-10-23  
**Auditor role:** Flutter / architecture / database / QA review

---

## 1. Executive summary

The source is a small, readable Flutter demo: about 44 Dart files (~140 KB) implementing product CRUD, a camera scanner, an in-memory cart, Bluetooth receipt printing, and shop details. It is a useful prototype, but it is **not a base for a production shop system**:

- data is stored in Hive (NoSQL) with no transactions, migrations, indexes, or relational integrity;
- completed sales and purchases are never persisted — there is no sales history, invoice record, stock movement, supplier, customer, debt, expense, or report;
- money is stored as `double` and displayed with the Indian rupee symbol;
- every string is hardcoded in English, with no Arabic/French localization and no RTL support;
- there are no automated tests beyond the generated placeholder widget test;
- the repository has **no LICENSE file**, which matters for code reuse (see §2).

We therefore **reuse the product intent and proven UX ideas** (camera scan → cart → receipt, ESC/POS printing approach) and **rebuild the application on a transactional SQLite foundation**. No source file is copied, because the repository grants no license.

The new application is called **HYDRA POS** and now lives at the repository root. The untouched audit clone was kept outside the repository as reference material.

---

## 2. License finding (important)

`git ls-files` finds no `LICENSE`, `COPYING`, or `NOTICE` file. GitHub shows no license. Under default copyright law, the code is **all rights reserved**: the public repository alone does not grant permission to copy, modify, or redistribute it.

Implication for this project:

- We do **not** copy source code from the reference audit clone into the new app.
- We reproduce only non-copyrightable ideas and generic patterns (feature set, scanner flow, ESC/POS command concept), and we write a new implementation.
- If you own the source repository, you may add a license and explicitly authorize reuse; otherwise the clean-room approach above is the safe one.
- The new project should carry its own license chosen by you. Until then, do not distribute it publicly.

---

## 3. What exists in the source

### 3.1 Architecture and dependencies

| Area | Finding |
|---|---|
| Pattern | Feature-first folders with `data` / `domain` / `presentation`, `fpdart` `Either`, use cases |
| State | `flutter_bloc` (billing/product/shop/printer) + `get_it` |
| Routing | `go_router` with 7 routes |
| Storage | `hive` + `hive_flutter`, three boxes: `products`, `shop`, `settings` |
| Scanner | `mobile_scanner` 5.x, camera only, 2-second duplicate cooldown |
| Printer | `print_bluetooth_thermal` + hand-written ESC/POS bytes, no ESC/POS library |
| Other | `google_fonts`, `pretty_qr_code`, `vibration`, `permission_handler`, `uuid` |
| Tests | one generated `widget_test.dart` that does not exercise app logic |
| CI / docs | no CI; README claims “Clean Architecture”, “robust testability” and “offline-first” |

The layering is mostly cosmetic: presentation pages query Hive through blocs/use cases, but there is no transaction boundary, no persistent sale entity, and no separation for printing/catalog/reports.

### 3.2 Functional coverage

Implemented:

- add / edit / delete products (name, barcode, price, stock);
- camera barcode scan and lookup;
- cart with increment/decrement/remove;
- checkout screen with total;
- Bluetooth printer pairing via settings, saved MAC, raw ESC/POS receipt;
- shop name/address/phone/footer settings;
- rudimentary UPI QR (India-specific, wrong for Morocco).

Not implemented (despite being needed for a shop):

- persistent sales/invoices and invoice numbering;
- purchases, suppliers, purchase costs;
- stock movements, low-stock rules, expiry;
- customers, debts, partial payments;
- returns/refunds;
- expenses, cash reconciliation, reports;
- barcode quantity multipliers, packaging conversions (carton → units);
- external product catalogs;
- Arabic/French, RTL, MAD currency;
- CSV/Excel import, backup/restore, audit log;
- real printer abstraction, PDF invoices, sharing;
- tests, migrations, integrity constraints.

### 3.3 Concrete defects found

1. `ProductModel` uses `double price` — floating-point money errors are inevitable.
2. Checkout shows `₹` (mojibake in source) and the QR encodes `upi://` with `cu=INR`; unusable in Morocco.
3. Barcode is not unique; `firstWhere` silently returns the first duplicate.
4. Deleting a product deletes it permanently with no audit and no check for historical sales (there are none yet, but the design cannot support history).
5. Checkout “Print Receipt” is the only completion action; no sale is recorded, so printing failure loses the transaction and there is no reprint path.
6. Printer helper returns silently when disconnected (`if (!_isConnected) return;`) and reports success anyway.
7. `permission_handler` requests location permission for Bluetooth scanning; modern Android needs `BLUETOOTH_SCAN` with `neverForLocation`, not location.
8. `google_fonts` may download fonts at runtime, contradicting offline-first.
9. Receipt item names are truncated to 16 characters; prices and totals are unaligned; non-Latin text is not supported.
10. No idempotency: a slow double tap or duplicate scan frame can duplicate an operation.
11. No database migration strategy; Hive adapters are registered without versioning.
12. No storage of cost price, so profit cannot be computed.
13. No pagination; the whole product box is loaded into every list.
14. Hardcoded colors/text, no theme extension, no accessibility labels, no large-text/RTL checks.

### 3.4 What is worth reusing

| Idea | Decision |
|---|---|
| Camera scan → cart → receipt flow | Reuse the UX concept, reimplemented with debouncing and quantity multipliers |
| ESC/POS receipt structure | Reuse the concept, rebuilt behind a printer abstraction with proper status/error handling |
| Feature-oriented folder layout | Keep a layered layout, simplified for testability |
| `get_it` service locator | Keep |
| `flutter_bloc` | Replace with lightweight `ChangeNotifier` controllers for POS/purchase only; read screens use `FutureBuilder`. Less boilerplate, same testability. |
| Hive | Replace with SQLite (`sqflite`) + transactions + migrations |
| `go_router` | Replace with plain `Navigator` + one shell with bottom navigation/drawer. The app has no deep links; this reduces routing risk. |
| `google_fonts` | Remove; use system fonts offline |
| Indian UPI QR | Remove |
| Source code | Do not copy (no license) |

---

## 4. External catalog research (executed during audit)

**Open Food Facts v3** was called live with an identifying User-Agent on 2026-10-23:

- `GET https://world.openfoodfacts.org/api/v3/product/{barcode}.json?fields=...` → HTTP 200, `status: success` for found products.
- A missing barcode (`6111245100059`) returns HTTP 404 with `status: failure`, not a crash.
- The older v2 endpoint also works, but v3 is the documented choice for new integrations.
- Search was used only to find sample Moroccan barcodes, not to bulk-download.

Sample results (actual API responses, accents normalized here):

| Barcode | Product | Brand | Size | Found |
|---|---|---|---|---|
| 6111035000430 | Sidi Ali | Les Eaux Minérales d'Oulmès | 33 cl | yes |
| 6111035000058 | Eau minérale naturelle | Sidi Ali | 1,5 L | yes |
| 6111035002175 | Sidi Ali | Sidi Ali | 2 L | yes |
| 6111035000027 | Sidi Ali | Sidi Ali | 50 cl | yes |
| 6111035001383 | Eau minerale | Sidi Ali | 75 cl | yes |
| 6111021090049 | Concentré de tomates Aicha | Les Conserves de Meknès | 370 g | yes |
| 6111021090056 | Aicha Tomato Paste | Aicha | 730 g | yes |
| 6111021090100 | Double concentré de tomate | Aicha | — | yes |
| 6111245100059 | — | — | — | **no** |

Conclusion: coverage for major Moroccan packaged brands exists but is **incomplete and inconsistent** (names may be missing, duplicated, or not in Arabic). The app must always permit fast manual entry and must never block a sale/purchase on a lookup. **Open Products Facts** is integrated as a secondary provider; its coverage is much smaller and it must be treated as optional.

Licensing/terms: OFF/OPF data is published under the Open Database License (ODbL); attribution is required. We send only a barcode and an identifying User-Agent, never shop, customer, or financial data, and we do not bulk-download.

---

## 5. Target architecture

```
Flutter (Android-first)
├── Presentation: screens + a few ChangeNotifier controllers
├── Domain services: sale, purchase, inventory, returns, cash, reports,
│                    catalog, invoice PDF, printing, backup
├── Data access: typed repositories over sqflite
├── SQLite database (single file, WAL, FK on, migrations)
└── Integrations: Open Food Facts, Open Products Facts, ESC/POS printer,
                  Android share/print, file import/export
```

Key decisions:

1. **SQLite + `sqflite`**, with `sqflite_common_ffi` for Windows/CI tests.
2. **Integer money**: centimes (`12,50 DH` = `1250`). No `double` for money.
3. **Integer quantities**: milli-units (1 piece = 1000, 0.5 kg = 500). Packaging factors are exact.
4. **Stock is updated only inside the same transaction** that writes the sale/purchase/return/adjustment and its movement row.
5. **Idempotency key** on sales prevents duplicate commits from double taps or retries.
6. **Invoice numbers** come from a transactional sequence table; history is immutable. Corrections are voids/returns with audit records.
7. **Snapshots** of product name, barcode, unit, price, and cost are stored on every transaction line, so history survives product edits/deletes.
8. **Weighted-average cost** per base unit, updated on purchase. Reports label profit as estimated and expose missing-cost counts.
9. **Custom lightweight localization** (`fr` / `ar`), with `MaterialApp.locale` driving RTL. No runtime translation service.
10. **Catalog provider interface** so more sources can be added without touching sales/inventory.
11. **Printer interface** with a Bluetooth ESC/POS implementation and a PDF/share fallback. Printing never participates in the sale transaction.

### 5.1 Database entities

`settings`, `shop`, `categories`, `suppliers`, `customers`, `products`,
`product_units`, `batches`, `sales`, `sale_lines`, `sale_returns`,
`return_lines`, `purchases`, `purchase_lines`, `payments`, `expenses`,
`cash_sessions`, `stock_movements`, `ledger_entries`, `audit_log`,
`sequences`, `catalog_cache`.

Full DDL, indexes, and migration path: `docs/DATABASE.md`.

### 5.2 Documented accounting rules

- Revenue = completed sales total − returns total (net of discounts).
- COGS = sold base quantity × cost snapshot on the sale line, minus returned quantities at their cost snapshot.
- Gross profit = revenue − COGS (estimated; missing costs highlighted).
- Net operating profit = gross profit − expenses in the period (only when expenses are recorded).
- Customer balance > 0 means the customer owes the shop. Supplier balance > 0 means the shop owes the supplier.
- Cash reconciliation counts actual cash movements only: cash sale amounts applied, customer cash payments, supplier cash payments, cash expenses, cash refunds. Credit sale creation and later credit settlement are not double counted.
- These are management figures, not tax/legal statements. No tax compliance is claimed.

### 5.3 Packaging model

- Stock is stored in the product's base unit (piece, kg, L).
- A package row stores `factor_milli` base units (e.g. carton of 12 bottles = 12000).
- Purchase/sale by carton multiplies quantity by the factor; unit cost/price is converted to the base unit for stock and profit.
- Optional package prices are honored exactly for whole packages; otherwise derived from the base price with half-up rounding.

---

## 6. Staged plan and acceptance mapping

| Phase | Work | Acceptance evidence |
|---|---|---|
| 1 (this report) | Inspect repo, license, architecture, DB, features; catalog coverage test | This document; live API evidence |
| 2 Foundation | Flutter project, SQLite schema/migrations, FR/AR + RTL, MAD, product CRUD, barcode scan, multipliers, packaging, OFF/OPF lookup + cache, manual fallback | Unit tests + offline fallback tests + UI RTL test |
| 3 Operations | POS, sales persistence, stock movements, purchases, suppliers, customers, debts, payments, returns/voids | Transactional service tests |
| 4 Invoices/printing | Invoice history, PDF generation, share, printer abstraction, reprint, auto-print option | PDF/reprint tests; no printer hardware claimed |
| 5 Business tools | Expenses, cash sessions, reports/charts, expiry, stocktake, CSV/Excel import, CSV export, backup/restore, audit log | Service tests, import validation tests, backup round-trip test |
| 6 QA | `dart format`, `flutter analyze`, `flutter test`, Android debug build if toolchain permits; docs | Command output reported honestly |

Order is unchanged from the brief. Foundation precedes operations because every operation needs the schema, money/quantity types, and localization. Catalog lookup is implemented early, as required.

---

## 7. Risks and limitations to verify during delivery

- **Moroccan barcode coverage** is not guaranteed. Tests use representative barcodes plus mocked responses; manual entry is always available.
- **Printer hardware is not available in this environment.** The Bluetooth implementation can be compiled and its command generation unit-tested, but no physical printer model can be certified as “tested”. The UI/docs will state this.
- **Arabic in PDF/ESC-POS**: PDF uses a bundled Latin/Arabic font; basic ESC/POS printers often lack Arabic code pages. PDF/share is the reliable fallback; this will be documented.
- **Android toolchain**: Flutter and Android SDK are not pre-installed here. They will be installed if download/time permits; otherwise the report will clearly state which commands were not executed.
- **No user authentication** exists, so the audit log records actions and timestamps, not identified users; we will not claim otherwise.
- **No central/cloud sync**; the data model leaves room for a shared catalog but the MVP is local-only.

---

## 8. Deliverables

- Working app at the repository root (`lib/`, `android/`, `test/`, `assets/`).
- `docs/PHASE1_AUDIT.md` (this file), `docs/ARCHITECTURE.md`, `docs/DATABASE.md`, `docs/CATALOG.md`, `docs/PRINTING.md`, `docs/TESTING.md`, `docs/STATUS.md`, `docs/USER_GUIDE.md`.
- Tests under `test/`.
- The audit clone is preserved outside the repository for reference; it is not part of the build or the licence.
