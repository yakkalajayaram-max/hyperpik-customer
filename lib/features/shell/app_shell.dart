import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nav.dart';
import '../../core/place.dart';
import '../account/account_screen.dart';
import '../account/addresses_screen.dart';
import '../category/categories_tab.dart';
import '../home/home_screen.dart';
import '../orders/orders_screen.dart';
import '../orders/review_prompt.dart';
import 'nav_bar.dart';

/// Home, Categories, Orders, Account. Which tab is showing lives in [shellTab], so a screen deep in a stack can send the
/// customer to Orders (after a push notification) without touching the shell.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    shellTab.addListener(_changed);
    Place.instance.autoSelect();
    // Asked a few seconds after the app opens, once per start, so it does not fight the first screen for attention.
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) ReviewPrompt.maybeAsk(context);
    });
  }

  @override
  void dispose() {
    shellTab.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _visited.add(shellTab.value));
  }

  @override
  Widget build(BuildContext context) {
    final tab = shellTab.value;
    // A tab is built the first time it is opened, then kept, so Home does not reload every time you come back to it.
    Widget page(int i, Widget w) => _visited.contains(i) ? w : const SizedBox.shrink();
    return ShellScope(
      child: Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          page(tabHome, const HomeScreen()),
          page(tabCategories, const CategoriesTab()),
          page(tabOrders, OrdersScreen(key: ValueKey('orders-${tab == tabOrders}'))),
          page(tabAccount, const AccountScreen()),
          page(tabAddresses, const AddressesScreen()),
        ],
      ),
      bottomNavigationBar: AppNavBar(
        selected: tab,
        onSelect: (i) {
          HapticFeedback.selectionClick();
          shellTab.value = i;
        },
      ),
    ));
  }
}
