# Product Requirements Document
## Personal Finance & Expense Management App (macOS + iOS)

---

## 1. Overview

A privacy-conscious, native Apple personal finance app that minimizes manual data entry through screenshot-based transaction capture, on-device intelligence, and deep OS integration (widgets, Siri, Live Activities). The app unifies authentication across providers into a single account and supports individual as well as shared/family budgeting.

---

## 2. Goals

- Reduce manual expense entry through screenshot parsing of payment apps
- Provide real-time visibility into spending, budgets, and net worth
- Offer proactive financial insights (trends, anomalies, forecasts) without requiring the user to dig for them
- Deliver a fully native, OS-integrated experience (widgets, Shortcuts, Live Activities, Handoff)
- Keep sensitive financial data processing on-device wherever possible

---

## 3. Platform Requirements

- **Platforms:** macOS, iOS (universal account, synced state)
- **Distribution:** Apple Developer Program required (paid) — CloudKit, App Groups, Push Notifications, Live Activities, and App Intents/Siri all depend on it
- **Data sync:** CloudKit (per-user private database; shared budgets use CloudKit shared zones)
- **On-device ML:** Vision/CoreML for screenshot parsing — no cloud upload of financial screenshots

---

## 4. Feature Set by Phase

Phases are ordered by dependency, not time. A feature is only placed in a phase once its prerequisites exist.

---

### Phase 1 — Foundation (Account, Data Model, Manual Tracking)

Everything else in the app depends on this phase existing first.

- **Authentication**
  - Sign in with Apple ID, Google ID, GitHub
  - Unified account regardless of provider (single user identity mapped across providers)
  - *Dependency:* None — must be built first, everything else attaches to a user account
- **Onboarding / Profile Setup**
  - First name, last name, mobile number, age, preferred tracking currency, monthly income, other profile fields
  - *Dependency:* Requires Authentication
- **Monthly Budget / Spending Cap**
  - Single overall cap definition
  - *Dependency:* Requires Profile (monthly income context)
- **Expense Categories**
  - Default categories: Food, Travel, Rent, Health, EMI/Bills, Investment, Grocery Shopping, Subscriptions
  - Custom category creation
  - *Dependency:* None beyond Authentication
- **Manual Transaction Entry**
  - Core transaction data model (amount, category, date, note, payment method)
  - *Dependency:* Requires Categories
- **Core Data Model / Local Storage**
  - CoreData/SwiftData schema for transactions, budgets, categories, reminders
  - *Dependency:* Foundational — required by every subsequent feature

---

### Phase 2 — Apple-Native Essentials

Requires Phase 1 data model to exist so widgets/Shortcuts have something to read.

- **Widgets** — today's spend, budget left, upcoming bills
  - *Dependency:* Requires App Groups (shared container between app and widget extension) + Phase 1 transaction/budget data
- **Home Screen / Lock Screen Widgets (iOS)**
  - *Dependency:* Same as above
- **Face ID Lock (iPhone)**
  - *Dependency:* None beyond Authentication — can be built independently
- **Local Notifications**
  - Daily reminders, weekly summaries (locally scheduled, not push-based)
  - *Dependency:* Requires Phase 1 budget/transaction data to generate summary content

---

### Phase 3 — Screenshot Capture & Auto-Processing

The most technically demanding phase; depends on Phase 1's transaction model to write into.

- **Screenshot Upload**
  - Users add screenshots from UPI apps (Google Pay, PhonePe, Paytm), banks, wallets
  - *Dependency:* Requires Phase 1 transaction data model as the write target
- **On-Device ML Parsing**
  - Vision/CoreML text extraction + structured parsing into transaction fields (amount, merchant, date)
  - *Dependency:* Requires Screenshot Upload
- **Auto-Detect Bills from Screenshots/SMS**
  - *Dependency:* Requires On-Device ML Parsing
- **Merchant-Based Auto-Categorization**
  - Learns category mapping per merchant over time
  - *Dependency:* Requires parsed transactions with merchant field populated (i.e., Screenshot Parsing) — needs a transaction history to learn from

---

### Phase 4 — Intelligence & Insights

Depends on a meaningful transaction history existing (Phase 1 + Phase 3 feeding data in).

- **Spending Trends** (month-over-month, category-wise charts)
  - *Dependency:* Requires sufficient transaction history (Phase 1/3)
- **Anomaly Detection** (unusual/large transactions flagged)
  - *Dependency:* Requires Spending Trends baseline to define "normal"
- **Recurring Subscription Detection & Renewal Alerts**
  - *Dependency:* Requires Merchant Auto-Categorization + transaction history (recurring pattern detection needs repeated merchant entries)
- **Cash Flow Forecast** (predicted balance based on upcoming bills/income)
  - *Dependency:* Requires Auto-Detect Bills (Phase 3) + Profile income data (Phase 1)
- **Net Worth Tracker** (assets - liabilities, linked accounts)
  - *Dependency:* Requires a new "accounts/assets" data model extension — not dependent on transactions, but should follow core app stability
- **Financial Notifications** — weekly summary, bi-monthly insights
  - *Dependency:* Requires Spending Trends + push notification entitlement (Apple Developer Program)

---

### Phase 5 — Budgeting Depth

- **Rollover Budget** (toggleable — unused amount carries to next month)
  - *Dependency:* Requires Phase 1 budget cap logic
- **Goal-Based Savings** (e.g., "Save ₹50k for trip by Dec")
  - *Dependency:* Requires Phase 1 transaction/budget data to track progress against
- **Shared / Family Budgets**
  - Multiple users on one budget with permissions (who can edit vs. view)
  - *Dependency:* Requires CloudKit shared zones + a permissions model added to the data schema — should follow Phase 1 stabilizing, since it changes the budget data structure

---

### Phase 6 — Advanced Apple-Native Integration

The most entitlement-heavy phase — requires Apple Developer Program features and a stable data layer everywhere else feeds from.

- **Siri Shortcuts / App Intents** ("Log ₹200 for lunch")
  - *Dependency:* Requires Phase 1 transaction entry logic exposed via App Intents
- **Live Activities** (real-time budget tracking on Lock Screen/Dynamic Island)
  - *Dependency:* Requires Phase 1 budget engine running reliably + App Groups
- **Handoff** (iPhone/Mac/iPad continuity)
  - *Dependency:* Requires CloudKit sync (Phase 5) to have cross-device state to hand off

---

### Phase 7 — Custom Reminders

- **Custom Payment Reminders** (title, frequency, time, amount)
  - *Dependency:* Requires Phase 1 data model + Local Notifications (Phase 2) as the delivery mechanism; benefits from Auto-Detect Bills (Phase 3) for suggesting reminders, but can function standalone

---

## 5. Non-Functional Requirements

- **Privacy:** No financial screenshot leaves the device unencrypted; ML parsing happens on-device
- **Security:** Face ID gating for app access on iPhone; CloudKit private/shared database encryption
- **Reliability:** Offline-first — manual entry and viewing must work without network
- **Extensibility:** Category system, reminder system, and account/asset model should support user-defined types beyond the defaults

---

## 6. Dependency Summary (Quick Reference)

| Feature | Depends On (Technical) | Requires Paid Apple Developer Program? |
|---|---|---|
| Sign in with Apple | — | **Yes** |
| Onboarding/Profile | Authentication | No |
| Budget Cap | Profile | No |
| Manual Transactions | Categories | No |
| Widgets | App Groups, Core Data Model | **Yes** (App Groups entitlement) |
| Local Notifications | Budget/Transaction Data | No |
| Face ID Lock | Authentication | No |
| Screenshot Upload | Core Data Model | No |
| ML Parsing (on-device) | Screenshot Upload | No |
| Auto-Detect Bills | ML Parsing | No |
| Merchant Auto-Categorization | ML Parsing (transaction history) | No |
| Spending Trends | Transaction History | No |
| Anomaly Detection | Spending Trends | No |
| Subscription Detection | Merchant Auto-Categorization | No |
| Cash Flow Forecast | Auto-Detect Bills, Profile Income | No |
| Net Worth Tracker | New Accounts/Assets Data Model | No |
| Financial Notifications (push-based) | Spending Trends | **Yes** (Push Notification entitlement) |
| Rollover Budget | Budget Cap Logic | No |
| Goal-Based Savings | Transaction/Budget Data | No |
| Shared/Family Budgets | Permissions Model | **Yes** (CloudKit shared zones) |
| Siri Shortcuts / App Intents | App Intents on Transaction Entry | **Yes** (App Intents entitlement) |
| Live Activities | Budget Engine, App Groups | **Yes** (Live Activities entitlement) |
| Handoff | Cross-device sync | **Yes** (CloudKit) |
| Custom Reminders | Local Notifications | No |

### Non-Code Dependencies Beyond Apple Developer Program

| Item | Needed For | Notes |
|---|---|---|
| Apple Developer Program ($99/yr) | CloudKit, App Groups, Push, Live Activities, App Intents, Sign in with Apple | Required before any of these can be implemented, tested on-device beyond 7 days, or distributed via TestFlight |
| Google Cloud Console project (OAuth credentials) | Sign in with Google | Needed to register OAuth client ID/secret |
| GitHub OAuth App registration | Sign in with GitHub | Needed to register OAuth client ID/secret |
| Apple Push Notification service (APNs) certificate/key | Push-based financial notifications | Generated via Apple Developer account, separate setup from base membership |
| CloudKit container configuration | Sync, Handoff, Shared Budgets | Set up in Apple Developer portal + Xcode capabilities |
| TestFlight | Installing on personal device without cable-connecting every 7 days, or sharing with testers | Requires paid account |
| App Store Connect record (even if unpublished) | Required to configure Sign in with Apple, Push, and TestFlight | Can stay in "not submitted" state indefinitely — doesn't require public release |

---

## 7. Out of Scope (v1)

- Direct bank/UPI API integrations (screenshot-based only for now)
- Investment/stock market module
- Physical receipt OCR (beyond app screenshots)
- Web/Android clients
