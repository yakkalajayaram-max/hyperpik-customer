import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/place.dart';
import '../../core/theme.dart';

const _seenKey = 'intro_seen_v1';

/// Whether this phone has already been through the welcome screens.
Future<bool> introSeen() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_seenKey) ?? false;
  } catch (_) {
    return true;
  }
}

/// Three short welcome screens on first launch, ending with the one permission that makes the app useful: location.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _locating = false;

  static const _pages = [
    ('🛍️', 'Local Shops,\nBigger Smiles ♥', 'Order from your favourite neighbourhood shops, with no hidden fees.'),
    ('📍', 'Watch it come to your door', 'Follow your order live on the map, from the kitchen to your doorstep.'),
    ('💜', 'Zero hidden fees', 'No package, platform or payment fee. What you see is what you pay.'),
  ];

  Future<void> _finish({bool withLocation = false}) async {
    if (withLocation) {
      setState(() => _locating = true);
      await Place.instance.useCurrent();
    }
    try {
      await (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    } catch (_) {}
    HapticFeedback.mediumImpact();
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1280), Color(0xFF140B3A), Color(0xFF0B0716)])),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _finish(), child: const Text('Skip', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800))),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Center(
                        child: Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(56),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          alignment: Alignment.center,
                          child: i == 0
                              ? ClipRRect(borderRadius: BorderRadius.circular(34), child: Image.asset('assets/brand/logo.png', width: 112, height: 112))
                              : Text(p.$1, style: const TextStyle(fontSize: 86)),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(p.$2, style: const TextStyle(color: Colors.white, fontSize: 36, height: 1.1, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      const SizedBox(height: 14),
                      Text(p.$3, style: const TextStyle(color: Colors.white70, fontSize: 17, height: 1.45)),
                    ]),
                  );
                },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: i == _page ? Hp.accentHi : Colors.white24, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: last
                  ? Column(children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                        onPressed: _locating ? null : () => _finish(withLocation: true),
                        icon: const Icon(Icons.my_location_rounded),
                        label: Text(_locating ? 'Finding you…' : 'Use my location'),
                      ),
                      TextButton(onPressed: _locating ? null : () => _finish(), child: const Text('Not now', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800))),
                    ])
                  : FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                      onPressed: () => _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
                      child: Text(_page == 0 ? 'Get Started' : 'Next'),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
