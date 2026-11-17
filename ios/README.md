# Family OS: the real iPhone app (SwiftUI + Supabase)

Stage 1 of the native app: parent sign-in, create family, add members,
link a child's iPhone with a QR code (no password for kids), and My Day.
The web prototype (`index.html`, `family-view.html`) stays as the design reference.

## Run it on the Mac (Demo mode, no server needed)

1. Install **Xcode** from the Mac App Store, open it once and accept the license.
2. In Terminal:
   ```sh
   brew install xcodegen          # needs Homebrew: https://brew.sh
   git clone https://github.com/Ajijaens-creator/Myfamily ~/Developer/Myfamily
   cd ~/Developer/Myfamily/ios
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   xcodegen generate
   open FamilyOS.xcodeproj
   ```
3. Pick an iPhone simulator at the top of Xcode and press ▶︎.
   With empty keys the app runs in **Demo mode** with the sample family.
   In Profile you can switch who holds the phone.

## Connect the real family server (Supabase)

1. Create a Supabase project (region: Singapore is closest to Jakarta).
2. Run `supabase/migrations/*.sql` (SQL editor, or `supabase db push`).
3. Authentication › Sign In / Providers: turn on **Email** and **Allow anonymous sign-ins**
   (kids' phones join anonymously, then the QR code links them to their profile).
4. Put the project host and anon key in `ios/Config/Secrets.xcconfig`:
   ```
   SUPABASE_HOST = abcdefgh.supabase.co
   SUPABASE_ANON_KEY = eyJ...
   ```
   This file is git-ignored. The anon key is safe in the app: every table is protected by Row Level Security.

## Put it on the kids' iPhones (TestFlight)

1. Apple Developer Program (Individual, USD 99/year): https://developer.apple.com/programs/enroll
2. Xcode › Settings › Accounts: add the Apple ID. Target FamilyOS › Signing & Capabilities: pick the Team.
3. App Store Connect › My Apps › **+** New App, bundle id `com.jaensfamily.familyos`.
4. Xcode: destination *Any iOS Device*, Product › Archive › Distribute App › TestFlight.
5. App Store Connect › TestFlight › Internal Testing: add family Apple IDs. Each child installs
   the **TestFlight** app, accepts the invite, taps Install. Children under 13 need to be in
   the Apple Family Sharing group for their Apple ID.

## How it fits together

| Part | Where |
|---|---|
| Database tables, Row Level Security, pairing and My Day functions | `supabase/migrations/` |
| Security tests (child can't see siblings, can't change rules, one-time codes...) | `supabase/tests/stage1_rls_test.sql` |
| App screens | `ios/FamilyOS/Views/` |
| Server calls (real + Demo) | `ios/FamilyOS/Core/Backend.swift` |
| Themes (Kids Boy, Kids Girl, Teen, Parent) | `ios/FamilyOS/Core/Theme.swift` |

CI (`.github/workflows/ios.yml`) runs the database tests on Postgres and builds the app on a macOS runner.
No NIK, KK number or home address is stored anywhere.
