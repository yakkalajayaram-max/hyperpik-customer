import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import 'category_screen.dart';

/// The Categories tab: every category as a tile, with a search box to narrow them.
class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  List<Category>? _categories;
  Map<String, int> _counts = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = Place.instance;
      final d = await Api.home(lat: p.isCurrent ? p.lat : null, lng: p.isCurrent ? p.lng : null);
      final counts = <String, int>{};
      for (final s in d.shops) {
        counts[s.category] = (counts[s.category] ?? 0) + 1;
      }
      if (mounted) {
        setState(() {
          _categories = d.catalog.isNotEmpty ? d.catalog : d.categories;
          _counts = counts;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _categories;
    final muted = Hp.muted(context);
    return SitePage(
      onRefresh: _load,
      bottom: 110,
      children: [
        const PageHeading(label: 'Browse', title: 'All categories'),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(24), child: Column(children: [Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: muted)), const SizedBox(height: 14), FilledButton(onPressed: _load, child: const Text('Try again'))]))
        else if (all == null)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
        else
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: all.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: categoryTileExtent(context)),
            itemBuilder: (_, i) => CategoryTile(category: all[i], count: all[i].shops > 0 ? all[i].shops : _counts[all[i].label]),
          ),
      ],
    );
  }
}

