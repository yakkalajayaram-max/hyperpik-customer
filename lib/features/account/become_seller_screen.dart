import 'package:flutter/material.dart';
import '../support/in_app_page.dart';

import '../../core/site_chrome.dart';
import '../../core/theme.dart';

/// "List your shop on Hyperpik": what a shop gets, and a button to the website's seller onboarding.
class BecomeSellerScreen extends StatelessWidget {
  const BecomeSellerScreen({super.key});

  static const _benefits = [
    (Icons.groups_rounded, 'Reach more customers', 'in your neighbourhood'),
    (Icons.money_off_csred_rounded, 'Zero platform fee', 'keep what you earn'),
    (Icons.storefront_rounded, 'Easy store setup', 'menu, prices and hours in minutes'),
    (Icons.trending_up_rounded, 'Grow your business', 'orders, delivery and payouts handled'),
  ];

  @override
  Widget build(BuildContext context) {
    return SitePage(
      bottom: 40,
      children: [
        const PageHeading(label: 'For business', title: 'List your shop on Hyperpik', gap: 16),
        Padding(padding: const EdgeInsets.only(bottom: 24), child: Text('Reach more customers in your neighbourhood. Local shops, bigger smiles.', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)))),
        for (final b in _benefits)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(context),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Hp.tint(context), borderRadius: BorderRadius.circular(12)), child: Icon(b.$1, color: Hp.accent, size: 20)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.$2, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                  Text(b.$3, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(onPressed: () => openSitePage(context, 'Become a seller', '/vendor/onboarding'), child: const Text('Become a seller')),
        ),
      ],
    );
  }
}
