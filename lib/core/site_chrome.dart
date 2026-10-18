import 'dart:async';

import 'package:flutter/material.dart';

import '../features/account/notifications_screen.dart';
import '../features/account/sign_in_screen.dart';
import '../features/home/location_sheet.dart';
import 'api.dart';
import 'cart_dock.dart';
import '../features/shell/nav_bar.dart';
import 'nav.dart';
import 'orders_models.dart';
import 'place.dart';
import 'theme.dart';

/// A search typed on any screen but Home: Home picks it up, runs it and shows the results.
final ValueNotifier<String> homeSearch = ValueNotifier('');

/// A category chosen on another screen: Home picks it up and narrows itself to that category's shops.
final ValueNotifier<String?> homeCategory = ValueNotifier(null);

/// Takes a search from a screen that is not Home to Home's results.
void searchFromAnywhere(BuildContext context, String query) {
  if (query.trim().isEmpty) return;
  Navigator.of(context).popUntil((r) => r.isFirst);
  shellTab.value = tabHome;
  homeSearch.value = query.trim();
}

/// The top of every tab: where to deliver, the notifications bell, and the search box, in one compact block.
///
/// It scrolls away with the page and comes back the moment you scroll up (a pinned one would keep a fifth of the screen).
/// The logo and the bag are gone from here: the bag is the round button in the tab bar, and notifications are
/// the bell here, with the number unread on it. Account is in the tab bar.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.unread = 0, this.onAuthChanged, this.controller, this.onChanged, this.onSubmitted, this.floating = true});

  /// Unread notifications, shown as a count on the bell.
  final int unread;

  /// Called when the customer came back from signing in.
  final VoidCallback? onAuthChanged;

  /// Home searches as you type.
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  /// Everywhere else, a search is sent to Home when it is submitted.
  final ValueChanged<String>? onSubmitted;

  /// Comes back as soon as the page is scrolled up. A page with its own pinned bar turns this off.
  final bool floating;

  static const double _row = 48;
  static const double _search = 44;

  /// Height of the block under the status bar.
  static const double extent = 8 + _row + 8 + _search + 10;

  static String _area(String subtitle) {
    final parts = subtitle.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).take(2);
    return parts.join(', ');
  }

  Widget _location(BuildContext context) {
    return ListenableBuilder(
      listenable: Place.instance,
      builder: (context, _) {
        final place = Place.instance;
        final note = place.awayNote;
        final sub = !place.isCurrent
            ? 'Choose where to deliver'
            : note ?? (place.savedAddress ? 'Saved address' : (_area(place.subtitle).isEmpty ? 'Tap to change' : _area(place.subtitle)));
        return InkWell(
          onTap: () => showLocationSheet(context),
          borderRadius: BorderRadius.circular(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              place.locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.location_on_rounded, color: Hp.accent, size: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  place.isCurrent ? place.label : 'Add an address',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.3, fontWeight: note != null ? FontWeight.w700 : FontWeight.w500, color: note != null ? Hp.warn : Hp.muted(context)),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _bell(BuildContext context) {
    if (Api.user == null) {
      return SizedBox(
        height: 40,
        child: FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18), elevation: 0),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen(popOnSuccess: true))).then((_) => onAuthChanged?.call()),
          child: const Text('Log in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      );
    }
    // The bell, with the unread count. Account is already in the tab bar below.
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () async {
        await showNotificationsPanel(context);
        onAuthChanged?.call();
      },
      child: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread', style: const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: Hp.bad,
        largeSize: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: Hp.tint(context), shape: BoxShape.circle),
          child: const Icon(Icons.notifications_none_rounded, size: 22, color: Hp.accent),
        ),
      ),
    );
  }

  Widget _searchBox(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Hp.line(context), width: 0.8));
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search stores & products',
        hintStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Hp.faint(context)),
        filled: true,
        fillColor: Hp.surface2(context),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: Hp.muted(context)),
        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Hp.accent, width: 1)),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: floating,
      snap: floating,
      pinned: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: extent,
      titleSpacing: 0,
      backgroundColor: Hp.surface(context),
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: Hp.line(context), width: 0.8)),
      title: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(height: _row, child: Row(children: [Expanded(child: _location(context)), const SizedBox(width: 12), _bell(context)])),
          const SizedBox(height: 8),
          SizedBox(height: _search, child: _searchBox(context)),
        ]),
      ),
    );
  }
}

/// "You are 320 m away" (or "You are here") under a saved address, measured from where the phone is. Nothing until a
/// position is known or when the address has no map pin.
class AwayNote extends StatelessWidget {
  const AwayNote(this.address, {super.key, this.fontSize = 12});
  final Address address;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Place.instance,
      builder: (_, __) {
        final text = Place.instance.distanceTo(address);
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(text, style: TextStyle(fontSize: fontSize, height: 1.33, fontWeight: FontWeight.w600, color: text == 'You are here' ? Hp.ok : Hp.warn)),
        );
      },
    );
  }
}

/// Runs [action] after the typing pauses.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 400)]);
  final Duration delay;
  Timer? _t;
  void run(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  void dispose() => _t?.cancel();
}

/// The tab bar for a page pushed over the tabs (a shop, an order, the cart), so it is on screen as it is on the website.
/// Inside the shell the shell's own bar is already there. Tapping a tab goes back to the tabs and shows that one.
Widget? pushedNavBar(BuildContext context) {
  if (ShellScope.inShell(context)) return null;
  return AppNavBar(
    selected: null,
    onSelect: (i) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      shellTab.value = i;
    },
  );
}

/// What a signed-out visitor sees on a page that needs an account: why, and a button into the login, not the login itself.
Widget loginPromptPage(BuildContext context, {required IconData icon, required String title, required String body, VoidCallback? onSignedIn}) {
  return SitePage(
    bottom: 40,
    onAuthChanged: onSignedIn,
    children: [
      const SizedBox(height: 8),
      EmptyCard(
        icon: icon,
        title: title,
        body: body,
        actionLabel: 'Log in',
        onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen(popOnSuccess: true))).then((_) => onSignedIn?.call()),
      ),
    ],
  );
}

/// A page of the website: the sticky bar and the location/search band, then the page's own content at 16 px from the
/// edges and 24 px from the band, as `<main className="px-4 py-6">` has it.
class SitePage extends StatelessWidget {
  const SitePage({super.key, required this.children, this.onRefresh, this.onAuthChanged, this.bottom = 24, this.unread = 0, this.bottomBar});
  final List<Widget> children;

  /// A bar pinned to the bottom of the screen while the page scrolls (the cart's pay bar), above the navigation bar.
  final Widget? bottomBar;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onAuthChanged;
  final double bottom;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        AppHeader(onAuthChanged: onAuthChanged, unread: unread, onSubmitted: (q) => searchFromAnywhere(context, q)),
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 0), sliver: SliverList(delegate: SliverChildListDelegate(children))),
        SliverToBoxAdapter(child: DockSpacer(base: bottom)),
      ],
    );
    final nav = pushedNavBar(context);
    return Scaffold(
      body: onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
      bottomNavigationBar: bottomBar == null ? nav : Column(mainAxisSize: MainAxisSize.min, children: [bottomBar!, ?nav]),
    );
  }
}

/// "History" over "My orders": the small label and the big page title.
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.label, required this.title, this.gap = 32});
  final String label;
  final String title;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.75)),
      ]),
    );
  }
}

/// The website's `.card`: surface, 0.8 px line, 16 radius.
BoxDecoration cardDecoration(BuildContext context) =>
    BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context).withValues(alpha: 0.8), width: 0.8));

/// The website's EmptyState: an icon plate, a title, a line of help and an optional button.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.title, this.body, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
      decoration: cardDecoration(context),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: Hp.tint(context), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, size: 24, color: Hp.accent),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
        if (body != null) ...[
          const SizedBox(height: 4),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 384), child: Text(body!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)))),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ]),
    );
  }
}

/// The website's StatusBadge chip.
enum BadgeTone { accent, ok, warn, bad, muted }

class HpBadge extends StatelessWidget {
  const HpBadge(this.text, {super.key, this.tone = BadgeTone.accent});
  final String text;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      BadgeTone.accent => (Hp.tint(context), Hp.accentHi),
      BadgeTone.ok => (Hp.ok.withValues(alpha: 0.1), Hp.ok),
      BadgeTone.warn => (Hp.warn.withValues(alpha: 0.1), Hp.warn),
      BadgeTone.bad => (Hp.bad.withValues(alpha: 0.1), Hp.bad),
      BadgeTone.muted => (Hp.surface2(context), Hp.muted(context)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}
