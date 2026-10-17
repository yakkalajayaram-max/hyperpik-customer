# Hyperpik customer app (Android)

Native Flutter app for customers: find shops near you, order, pay, track, get refund updates. Same Supabase project
and the same website backend as the vendor app and hyperpik.com, so pricing, fees, courier booking and payment
verification are done by one piece of code.

- Package: `com.hyperpik.customer` (permanent once published on Google Play).
- Talks to: Supabase (sign-in only) and `https://hyperpik.com/api/customer/*` (everything else).
- Distribution: Google Play Store.

## What exists (0.3.0)

| Area | State |
|---|---|
| First-run welcome and location ask | done |
| Home: header with delivery time, category grid, popular dishes, quick filters, shop cards | done |
| Category pages in each category's own colour, with search and filters | done |
| Shop page: menu by category, bestsellers, veg filter, search, floating Menu, cart bar | done |
| Dish choices (size, rice/noodles) and add-ons | done |
| Cart, checkout (server-priced), coupons, COD and Razorpay | done |
| Addresses with a map pin picker and place search (no maps key needed) | done |
| Orders: list, live tracking with a map, rider call, delivery code, cancel | done |
| Refund status card | done |
| Rate an order, order again, get help (routed as a ticket) | done |
| Favourites, notifications, edit profile | done |
| Sign in with a 6-box code or Google; delete account | done |
| Push notifications | built; needs the Firebase service key set on the server |

## Still to do

1. **Play release:** upload keystore (`android/key.properties`, see `key.properties.example`), store listing, privacy policy URL,
   data-safety form, closed testing track.
2. Push for the rider app (separate Firebase app id).

## Rules the app follows

- The server decides money. The app shows a cart total as an estimate and never sends prices that the server trusts.
- A shop that is closed or does not deliver to the customer is shown dimmed with the reason, not hidden.
- The anon key is the only key in the app. The service-role key never ships.

## Build

```bash
flutter pub get
flutter test
flutter build apk --release
```
