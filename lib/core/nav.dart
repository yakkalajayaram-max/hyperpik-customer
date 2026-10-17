import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Which bottom tab is showing. A screen deep in a stack (an order, a reorder) can send the customer to the Cart tab
/// without knowing anything about the shell.
final ValueNotifier<int> shellTab = ValueNotifier<int>(0);

// The bar matches the website's mobile bar: Home, Orders, a raised Cart button in the middle, Addresses, Account.
// Categories is not on the bar (the website's home has its category grid); it stays a page for deep links and "More".
const tabHome = 0;
const tabCategories = 1;
const tabOrders = 2;
const tabAccount = 3;
const tabAddresses = 4;

/// How tall the tab bar is above the phone's own gesture inset. The cart dock sits above it.
const double kNavExtent = 58;

/// Put around the tab shell: a page inside it must not add a second tab bar of its own.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required super.child});

  static bool inShell(BuildContext context) => context.getInheritedWidgetOfExactType<ShellScope>() != null;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}
