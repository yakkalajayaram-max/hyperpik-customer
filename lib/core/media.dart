import 'config.dart';

/// The same stock photos the website uses, so a category, a shop without a cover or a dish without a photo looks the
/// same in the app as on hyperpik.com. They live on the site (public/images) and are fetched, not bundled. A shop's own
/// uploads always win; these are for the shop that has not added photos yet.
class Media {
  Media._();

  /// Only four photo sets exist; every other category borrows the closest one (mirrors lib/media.ts on the website).
  static const _set = {
    'food': 'food',
    'grocery': 'grocery',
    'fashion': 'fashion',
    'electronics': 'electronics',
    'supermarket': 'grocery',
    'fruits_veg': 'grocery',
    'dairy': 'grocery',
    'fish_seafood': 'grocery',
    'meat_store': 'grocery',
    'pharmacy': 'grocery',
    'pet_supplies': 'grocery',
    'stationery': 'grocery',
    'jewellery': 'fashion',
    'beauty_care': 'fashion',
    'toys_baby': 'fashion',
    'sports_fitness': 'fashion',
    'gifts_flowers': 'fashion',
    'mobile_accessories': 'electronics',
    'home_kitchen': 'electronics',
    'furniture': 'electronics',
  };

  static String _kind(String? key) {
    if (key == null || key.isEmpty) return 'food';
    // A category an admin adds later gets the generic shop photos, not food.
    return _set[key] ?? 'grocery';
  }

  /// The website's string hash, so the same shop gets the same cover photo on both.
  static int _pick(String seed, int n) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return h % n;
  }

  static String _url(String kind, String file) => '${AppConfig.siteUrl}/images/$kind/$file';

  static String category(String key) => _url(_kind(key), 'category.jpg');

  static String cover(String key, String seed, [String? uploaded]) =>
      (uploaded != null && uploaded.isNotEmpty) ? uploaded : _url(_kind(key), 'cover-${_pick(seed, 2) + 1}.jpg');

  static String item(String key, String seed, [String? uploaded]) =>
      (uploaded != null && uploaded.isNotEmpty) ? uploaded : _url(_kind(key), 'item-${_pick(seed, 2) + 1}.jpg');
}
