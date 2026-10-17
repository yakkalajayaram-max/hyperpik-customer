import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/favourites.dart';
import '../../core/models.dart';
import '../../core/nav.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/widgets.dart';
import '../home/home_screen.dart';

/// The shops this customer has hearted, in the same card as the website's grid.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  List<Shop>? _shops;
  String? _error;

  @override
  void initState() {
    super.initState();
    Favourites.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Favourites.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = Place.instance;
      final s = await Api.favourites(lat: p.isCurrent ? p.lat : null, lng: p.isCurrent ? p.lng : null);
      if (mounted) setState(() => _shops = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = _shops;
    return SitePage(
      onRefresh: _load,
      bottom: 110,
      children: [
        const PageHeading(label: 'Saved', title: 'Your favourites'),
        if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(_error!, textAlign: TextAlign.center))
        else if (shops == null)
          const Column(children: [Skeleton(height: 271, radius: 16), SizedBox(height: 16), Skeleton(height: 271, radius: 16)])
        else if (shops.isEmpty)
          EmptyCard(
            icon: Icons.favorite_border_rounded,
            title: 'No favourites yet',
            body: 'Tap the heart on any shop to save it here.',
            actionLabel: 'Browse shops',
            onAction: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              shellTab.value = tabHome;
            },
          )
        else
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: shops.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, mainAxisExtent: 271),
            itemBuilder: (_, i) => StoreGridCard(shop: shops[i]),
          ),
      ],
    );
  }
}
