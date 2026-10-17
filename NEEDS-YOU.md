# Things only the owner can do

Kept aside while the build continues. Each item says what is needed and why I could not decide it.

| # | What | Why it needs you |
|---|---|---|
| 1 | Rotate the Firebase service-account key (Firebase → Project settings → Service accounts → new key, delete `03a0e113c1…`), then replace `FIREBASE_SERVICE_ACCOUNT` in Vercel | The old key was printed in a chat transcript |
| 2 | Google Maps API key (Android) | Needed for the address map-pin picker |
| 3 | Google Play developer account, upload keystore, store listing, privacy-policy URL, data-safety form | Account, payment and legal identity are yours |
| 4 | Place a real test order from the phone (cash on delivery first), accept it from the vendor app | Proves push end to end; an order moves real orders and money |
| 5 | Decide marketing consent: add a tick at signup, or keep broadcasts to everyone | A legal / policy choice |
Autonomous build window started 2026-10-14 19:52 IST; stop around 5 hours later.

## Rider platform (requested, built after the customer app polish)
- Payout / settlement to riders: left open on purpose (Razorpay Route vs something else) — your decision.
- Rider app is hidden from public: distributed by link only, no store listing.

## Added 15 Oct

- **Address search provider.** Search and "what is at this pin" use free OpenStreetMap services (Photon, with Nominatim as the
  fallback). Both are fair-use, shared and rate limited, and Photon was taking 20-30 s on the day we tested. Fine for launch
  week; before real traffic pick a paid geocoder (Google Places, Mapbox, or a self-hosted Photon) and swap it in
  `lib/maps/search.ts` on the web project. One file.
- **Home "Trending near you"** ranks by real orders in the last 90 days, and falls back to what nearby shops list. It is only as
  good as the menu photos: dishes with no photo show a coloured tile with the category emoji.

- **Pickup / takeaway for customers.** The website does not offer a customer pickup order either (only the shop's till does
  takeaway), so the app has none. Adding it is a product decision: pricing without delivery, a "ready for pickup" step
  and OTP at the counter. Say the word and it is a contained piece of work on both web and app.
- **Dish photos.** Cards and search rows fall back to a coloured tile when a dish has no photo. Photos are the single biggest
  lift left in how "alive" the home feels; a shop-side nudge to add them is worth more than any code now.

## Maps: why OpenStreetMap and not Google Maps

The website loads Google Maps with NEXT_PUBLIC_GOOGLE_MAPS_API_KEY, a browser key restricted by HTTP referrer. A referrer-
restricted key is rejected by the Android Maps SDK and by server-side geocoding, so the app cannot reuse it. The app uses
OpenStreetMap tiles with Photon/Nominatim search so it works without any key. To switch to Google: in Google Cloud create (or
edit) a key that allows "Maps SDK for Android" and "Places API" and is restricted to package `com.hyperpik.app` plus the
release SHA-1, and give it to me. That is a console action only you can take.
