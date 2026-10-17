/// Where the customer app talks to. The anon key is public by design and bounded by row-level security; the
/// service-role key must never appear in an app that can be unzipped.
class AppConfig {
  static const supabaseUrl = 'https://qaolnxcmmomyhftheknr.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhb2xueGNtbW9teWhmdGhla25yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY2MjExNzcsImV4cCI6MjEwMjE5NzE3N30.BHBXDNS3HwLkYYlO0uu_eJZ6iwprd6AXC9dFRn8AzVA';

  /// Everything beyond sign-in and plain reads goes through the website, so pricing, fees, courier booking and
  /// payment verification are done by one piece of code for the web and the app.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://hyperpik.com');

  /// The web OAuth client Supabase's Google provider uses (the same one the website signs in with). Native Google sign-in asks
  /// Google for an ID token for this audience and hands it to Supabase. Empty means native sign-in is not set up yet and the
  /// app falls back to the browser.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '363621135704-hhk5psqn36ilrog4fdk34eq24alss0br.apps.googleusercontent.com');

  static const phoneCountryCode = '+91';

  /// Matches the intent-filter in AndroidManifest.xml and the redirect allow-list in Supabase → Authentication.
  static const authRedirect = 'com.hyperpik.customer://login-callback';

  /// Where browsing starts when the customer has not shared a location: Hyderabad.
  static const defaultLat = 17.385;
  static const defaultLng = 78.4867;
  static const defaultPlace = 'Hyderabad';
}
