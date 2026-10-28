import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/cart.dart';
import 'core/cart_dock.dart';
import 'core/favourites.dart';
import 'core/config.dart';
import 'core/diagnostics.dart';
import 'core/place.dart';
import 'core/push.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'features/intro/intro_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shop/shop_screen.dart';

/// Development only: lay the app out as a phone-width column. See HyperpikApp.
const kPreviewFrame = bool.fromEnvironment('PREVIEW_FRAME');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Diagnostics.install();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  await Future.wait([Cart.instance.load(), Place.instance.load(), ThemeController.instance.load()]);
  runApp(const HyperpikApp());
  // After the first frame: asking for notification permission must never delay the app opening.
  Push.start();
  // The hearts, and again whenever someone signs in or out.
  Favourites.instance.load();
  Supabase.instance.client.auth.onAuthStateChange.listen((s) {
    Favourites.instance.load();
    // Signing in makes the saved addresses available, so the nearest one can now be picked.
    if (s.event == AuthChangeEvent.signedIn) Place.instance.autoSelect();
  });
}

class HyperpikApp extends StatelessWidget {
  const HyperpikApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the theme is changed in Account.
    return ListenableBuilder(listenable: ThemeController.instance, builder: (context, _) => _app());
  }

  Widget _app() {
    return MaterialApp(
      title: 'Hyperpik',
      debugShowCheckedModeBanner: false,
      theme: Hp.theme(Brightness.light),
      darkTheme: Hp.theme(Brightness.dark),
      // System by default: the phone decides, until the customer chooses Light or Dark in Account.
      themeMode: ThemeController.instance.mode,
      navigatorKey: appNavigatorKey,
      navigatorObservers: [DockRouteObserver()],
      // The cart dock floats above every screen, so a cart is one tap away wherever the customer is.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        // The clock and battery in the status bar, and the buttons at the bottom, follow the theme.
        final bars = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Hp.page(context),
          systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        );
        final app = AnnotatedRegion<SystemUiOverlayStyle>(value: bars, child: Stack(children: [if (child != null) child, const CartDock()]));
        if (!kPreviewFrame) return app;
        // Development only (--dart-define=PREVIEW_FRAME=true): show a phone-width column on a wide desktop browser tab, with
        // MediaQuery saying so, so the web build can be compared side by side with the website's mobile view.
        final mq = MediaQuery.of(context);
        return ColoredBox(
          color: Colors.black,
          child: Center(child: ClipRect(child: SizedBox(width: 375, child: MediaQuery(data: mq.copyWith(size: Size(375, mq.size.height)), child: app)))),
        );
      },
      // Development only: with PREVIEW_FRAME, ?shop=<handle> in the address opens that shop directly.
      home: kPreviewFrame && (Uri.base.queryParameters['shop'] ?? '').isNotEmpty ? ShopScreen(handle: Uri.base.queryParameters['shop']!) : const _Root(),
    );
  }
}

/// The welcome screens once, then the app.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _seen;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    introSeen().then((v) {
      if (mounted) setState(() => _seen = v);
    });
    // The brand splash is shown for a moment, not just until the first read finishes.
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null || !_splashDone) return const _Splash();
    if (!seen) return IntroScreen(onDone: () => setState(() => _seen = true));
    return const AppShell();
  }
}


/// The first thing on screen: the logo, the name and the line.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1280), Color(0xFF140B3A), Color(0xFF0B0716)])),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ClipRRect(borderRadius: BorderRadius.circular(32), child: Image.asset('assets/brand/logo.png', width: 112, height: 112)),
          const SizedBox(height: 20),
          const Text('hyperpik', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(height: 8),
          Text('Local Shops, Bigger Smiles ♥', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75))),
        ]),
      ),
    );
  }
}
