# MoneyIQ

A privacy-conscious, native Apple personal finance and expense management app
for macOS and iOS. It minimizes manual data entry through screenshot-based
transaction capture, on-device intelligence, and deep OS integration
(widgets, Siri, Live Activities), unifies authentication across providers
into a single account, and supports individual as well as shared/family
budgeting.

## What it does (full product vision)

- **One account, any sign-in.** Sign in with Apple, Google, or GitHub — all
  map to the same unified user identity, regardless of which provider you
  used.
- **Screenshot-based expense capture.** Add screenshots from UPI apps
  (Google Pay, PhonePe, Paytm), banks, or wallets, and on-device ML (Vision/
  CoreML) parses amount, merchant, and date — no manual typing, no cloud
  upload of financial screenshots.
- **Auto-categorization that learns.** Merchant-based category mapping
  improves the more you use the app.
- **Budgeting.** A single monthly spending cap to start, with rollover and
  goal-based savings ("Save ₹50k for trip by Dec") layered in later, plus
  shared/family budgets with per-member edit/view permissions.
- **Proactive insights.** Spending trends, anomaly detection on unusual
  transactions, recurring subscription detection with renewal alerts, and
  cash-flow forecasting based on upcoming bills and income.
- **Net worth tracking** across linked accounts/assets.
- **Deep OS integration.** Home/Lock Screen widgets, Face ID app lock, Siri
  Shortcuts / App Intents ("Log ₹200 for lunch"), Live Activities for
  real-time budget tracking, and Handoff across iPhone/Mac/iPad.
- **Custom reminders** for recurring payments (title, frequency, time,
  amount), with local notification delivery.
- **Privacy and reliability by design.** Financial screenshots never leave
  the device unencrypted, ML parsing is on-device, and manual entry/viewing
  works fully offline.

See [finance-app-prd.md](finance-app-prd.md) for the full phased breakdown
and dependency ordering. Phases are built in dependency order, not calendar
order — a feature only starts once whatever it needs already exists.

## What's actually built right now

This repo currently implements the earliest slice of **Phase 1
(Foundation)**, deliberately scoped to work without a paid Apple Developer
Program membership:

- **Unified auth across providers.** Sign in with Google and sign in with
  GitHub both work today, via `ASWebAuthenticationSession` + PKCE — no
  backend server, no embedded client secret. Signing in with a second
  provider under the same email links to the *same* local account instead of
  creating a duplicate, which is the "unified identity" requirement from the
  PRD. Sign in with Apple is fully coded but gated off behind a flag, since
  it needs the paid Developer Program (see below).
- **Local data model** (SwiftData): `UserAccount`, `LinkedIdentity`,
  `ExpenseCategory` (8 defaults seeded on first launch — Food, Travel, Rent,
  Health, EMI/Bills, Investment, Grocery Shopping, Subscriptions),
  `ExpenseTransaction`, `Budget`, `ReminderItem`.
- **Manual transaction entry**, a monthly budget cap model, and basic
  onboarding (name, mobile, age, income, preferred currency).
- **Fully offline** — no CloudKit sync yet, everything lives in a local
  SwiftData store (`cloudKitDatabase: .none`).

Everything else in the vision above — screenshot parsing, ML categorization,
insights, widgets, Siri, Live Activities, CloudKit sync/Handoff, shared
budgets — comes in later phases once its prerequisites exist (see
[Roadmap / deferred work](#roadmap--deferred-work-needs-a-paid-apple-developer-program)
below).

## Project structure

- `MoneyIQCore/` — Swift package shared by both apps: SwiftData models, auth
  logic, persistence. Has its own test target.
- `iOS/MoneyIQ/`, `macOS/MoneyIQ/` — thin app entry points per platform.
- `Shared/` — SwiftUI views shared by both app targets (sign-in, onboarding,
  home).
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. The
  `.xcodeproj` is generated from this and is gitignored — never edit it by
  hand, edit `project.yml` and regenerate.
- `Config/Secrets.xcconfig` — your local OAuth credentials (gitignored).
  `Config/Secrets.xcconfig.example` is the template.

## Running it locally

### Prerequisites

- Xcode 16+ (Swift 5.10 / SwiftData / `@Observable` need iOS 17+ / macOS 14+
  SDKs)
- [Homebrew](https://brew.sh)
- A free Apple ID is enough — no paid Developer Program needed for anything
  currently implemented

### First-time setup

```bash
brew install xcodegen   # if you don't have it
cd MoneyIQ
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # then fill it in — see below
xcodegen generate
open MoneyIQ.xcodeproj
```

Whenever you change `project.yml` (add a file, target, dependency), rerun
`xcodegen generate`.

### Set up sign-in (your side)

The app builds and runs without this, but the sign-in buttons will say "not
configured" until you do it:

1. **Google OAuth client** (free, no Apple account needed)
   - [Google Cloud Console](https://console.cloud.google.com/) → APIs &
     Services → Credentials → Create Credentials → OAuth client ID.
   - Application type: **iOS** — bundle ID `com.moneyiq.ios` (create a
     second one for `com.moneyiq.macos` if you want to test both targets).
   - Copy the client ID into `Config/Secrets.xcconfig` as
     `MIQ_GOOGLE_CLIENT_ID`. Leave `MIQ_GOOGLE_REDIRECT_URI` as
     `moneyiq://oauth/google` — it's already wired into both apps'
     `CFBundleURLTypes`.

2. **GitHub OAuth App** (free)
   - GitHub → Settings → Developer settings → OAuth Apps → New OAuth App.
   - Homepage URL: anything (e.g. `https://example.com`).
   - Authorization callback URL: `moneyiq://oauth/github` (must match
     exactly).
   - Copy the Client ID into `Config/Secrets.xcconfig` as
     `MIQ_GITHUB_CLIENT_ID`. **Never** put a client secret anywhere in the
     app — this flow is PKCE-only by design so nothing secret ships in the
     binary. If your GitHub OAuth App doesn't support PKCE for the token
     exchange, GitHub will reject it; that would need a small secret-holding
     backend, which is intentionally out of scope for now.

3. **Xcode signing** — open the project, select each target → Signing &
   Capabilities → pick your personal Apple ID team.

### Build and run

Open `MoneyIQ.xcodeproj` in Xcode, pick the `MoneyIQ-iOS` or `MoneyIQ-macOS`
scheme, and hit Run — or from the command line:

```bash
# Package tests
cd MoneyIQCore && xcrun --sdk macosx swift test

# Full app builds
xcodebuild -project MoneyIQ.xcodeproj -scheme MoneyIQ-macOS -destination 'platform=macOS' build
xcodebuild -project MoneyIQ.xcodeproj -scheme MoneyIQ-iOS -destination 'generic/platform=iOS Simulator' build
```

## Roadmap / deferred work (needs a paid Apple Developer Program)

Per the PRD's dependency table, these stay off until you enroll
($99/yr) — nothing to do about them now:

- Sign in with Apple (`AppleAuthProvider.isEnabledByBuild = true` + add the
  capability in Xcode)
- CloudKit sync, Handoff, shared/family budgets (switch
  `PersistenceController`'s `cloudKitDatabase` from `.none`)
- Home/Lock Screen widgets, Live Activities (need the App Groups
  entitlement)
- Push-based financial notifications (need an APNs key/certificate)
- Siri Shortcuts / App Intents
- Screenshot upload + on-device ML parsing, auto-categorization, spending
  trends, anomaly detection, subscription detection, cash-flow forecast, net
  worth tracking — these don't need the paid program technically, but they
  build on a meaningful transaction history and are sequenced for later
  phases per the PRD's dependency ordering
