import 'config.dart';

/// The same stock photos the website uses, so a category looks the same in the app as on
/// hyperpik.com. Items and shop covers never use them: without a photo they show their name (see item_photo.dart). They live on the site (public/images) and are fetched, not bundled. A shop's own
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

  static String _url(String kind, String file) => '${AppConfig.siteUrl}/images/$kind/$file';

  static String category(String key) => _url(_kind(key), 'category.jpg');


}
