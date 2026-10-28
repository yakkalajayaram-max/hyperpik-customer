// What /api/customer/* returns, as typed objects. Parsing is forgiving about missing fields so an older app keeps
/// working when the server adds some, and strict about nothing that would charge the wrong amount.

num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
String? _s(Object? v) => v == null ? null : '$v';

class Category {
  Category({required this.key, required this.label, this.icon, this.colorHex, this.shops = 0});
  final String key;

  /// How many live shops sell in this category right now (0 means none yet).
  final int shops;
  final String label;

  /// The category's own colour, "#RRGGBB", set by the admin.
  final String? colorHex;

  /// An emoji chosen by the admin for the category.
  final String? icon;
  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(key: '${j['key']}', label: '${j['label']}', icon: _s(j['icon']), colorHex: _s(j['color']), shops: _n(j['shops']).toInt());
}

class Promo {
  Promo({required this.id, required this.title, this.subtitle, this.imageUrl, this.href});
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? href;
  factory Promo.fromJson(Map<String, dynamic> j) =>
      Promo(id: '${j['id']}', title: '${j['title']}', subtitle: _s(j['subtitle']), imageUrl: _s(j['imageUrl']), href: _s(j['href']));
}

class Shop {
  Shop({
    required this.id,
    required this.handle,
    required this.name,
    required this.category,
    this.description,
    this.subtitle,
    this.addressLine,
    this.logoUrl,
    this.coverUrl,
    this.rating = 0,
    this.ratingCount = 0,
    this.prepMinutes = 0,
    this.city,
    this.distanceKm,
    this.inRange = true,
    this.open = true,
    this.closedReason,
    this.favourite = false,
    this.freeDeliveryOver,
    this.supportsDelivery = true,
    this.supportsPickup = false,
    this.categoryKey = '',
    this.categoryColor,
    this.displayTags = const [],
    this.deliveryMode,
    this.baseDeliveryFee = 0,
    this.createdAt,
    this.totalOrders = 0,
    this.offerLabel,
    this.family = 'general',
    this.layout,
  });

  final String id;
  final String handle;
  final String name;
  final String category;
  final String? description;

  /// What the website prints under the name on a shop card (cuisines, departments, brands...).
  final String? subtitle;

  /// Where the shop is, as the shop gave it.
  final String? addressLine;
  final String? logoUrl;
  final String? coverUrl;
  final double rating;
  final int ratingCount;
  final int prepMinutes;
  final String? city;
  final double? distanceKm;
  final bool inRange;
  final bool open;
  final String? closedReason;
  final bool favourite;
  final num? freeDeliveryOver;
  final bool supportsDelivery;
  final bool supportsPickup;
  final String categoryKey;
  final String? categoryColor;

  /// "FREE delivery", "Fast", "Pure veg" and the shop's own tags, as the website prints them on a card.
  final List<String> displayTags;
  final String? deliveryMode;
  final num baseDeliveryFee;
  final DateTime? createdAt;
  final int totalOrders;

  /// The headline offer for the card ("25% OFF"), when the shop or the platform is running one.
  final String? offerLabel;

  /// Which kind of product page this shop's items get: food, packaged, fresh, produce, pharmacy, apparel, electronics or general.
  final String family;

  /// How its product pages are arranged: food, apparel, electronics or grocery. Chosen by the admin per category; from an older
  /// server it is worked out from [family].
  final String? layout;

  String get productLayout => switch (layout) {
        'food' || 'apparel' || 'electronics' || 'grocery' => layout!,
        _ => switch (family) {
            'food' => 'food',
            'apparel' => 'apparel',
            'electronics' => 'electronics',
            _ => 'grocery',
          },
      };

  /// A shop can be ordered from only when it is open and delivers to where the customer is.
  bool get canOrder => open && inRange;

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
        id: '${j['id']}',
        handle: '${j['handle'] ?? j['slug']}',
        name: '${j['name']}',
        category: '${(j['category'] as Map?)?['label'] ?? ''}',
        description: _s(j['description']),
        logoUrl: _s(j['logoUrl']),
        coverUrl: _s(j['coverUrl']),
        rating: _n(j['rating']).toDouble(),
        ratingCount: _n(j['ratingCount']).toInt(),
        prepMinutes: _n(j['prepMinutes']).toInt(),
        city: _s(j['city']),
        distanceKm: j['distanceKm'] == null ? null : _n(j['distanceKm']).toDouble(),
        inRange: j['inRange'] != false,
        open: j['open'] != false,
        closedReason: _s(j['closedReason']),
        favourite: j['favourite'] == true,
        freeDeliveryOver: j['freeDeliveryOver'] == null ? null : _n(j['freeDeliveryOver']),
        supportsDelivery: j['supportsDelivery'] != false,
        supportsPickup: j['supportsPickup'] == true,
        categoryKey: '${(j['category'] as Map?)?['key'] ?? ''}',
        categoryColor: _s((j['category'] as Map?)?['color']),
        subtitle: _s(j['subtitle']),
        addressLine: _s(j['addressLine']),
        displayTags: ((j['displayTags'] as List?) ?? const []).map((e) => '$e').toList(),
        deliveryMode: _s(j['deliveryMode']),
        baseDeliveryFee: _n(j['baseDeliveryFee']),
        createdAt: DateTime.tryParse('${j['createdAt']}'),
        totalOrders: _n(j['totalOrders']).toInt(),
        offerLabel: _s(j['offerLabel']),
        family: _s(j['family']) ?? 'general',
        layout: _s(j['layout']),
      );
}

class Option {
  Option({required this.id, required this.name, required this.price});
  final String id;
  final String name;
  final num price;
  factory Option.fromJson(Map<String, dynamic> j) => Option(id: '${j['id']}', name: '${j['name']}', price: _n(j['price']));
}

class ChoiceGroup {
  ChoiceGroup({required this.id, required this.name, required this.isVariation, required this.min, required this.max, required this.options});
  final String id;
  final String name;

  /// A variation says WHICH version the dish is (a size, rice or noodles) and must be answered; an add-on is optional.
  final bool isVariation;
  final int min;
  final int max;
  final List<Option> options;

  bool get required => isVariation || min > 0;

  factory ChoiceGroup.fromJson(Map<String, dynamic> j) => ChoiceGroup(
        id: '${j['id']}',
        name: '${j['name']}',
        isVariation: j['kind'] == 'variation',
        min: _n(j['min']).toInt(),
        max: _n(j['max']).toInt() <= 0 ? 1 : _n(j['max']).toInt(),
        options: ((j['options'] as List?) ?? const []).map((o) => Option.fromJson(Map<String, dynamic>.from(o as Map))).toList(),
      );
}

/// One heading on a product page (ingredients, care, key specifications...): text, a list of chips, or label/value rows.
class DetailSection {
  DetailSection({required this.key, required this.title, this.text, this.list = const [], this.specs = const []});
  final String key;
  final String title;
  final String? text;
  final List<String> list;
  final List<({String label, String value})> specs;

  factory DetailSection.fromJson(Map<String, dynamic> j) => DetailSection(
        key: '${j['key']}',
        title: '${j['title']}',
        text: _s(j['text']),
        list: ((j['list'] as List?) ?? const []).map((e) => '$e').toList(),
        specs: [for (final x in ((j['specs'] as List?) ?? const [])) (label: '${(x as Map)['label']}', value: '${x['value']}')],
      );
}

/// A small tag on a product: "Vegetarian", "Organic", "Prescription required".
class ProductBadge {
  ProductBadge({required this.key, required this.label, required this.tone});
  final String key;
  final String label;

  /// ok, bad, warn or plain.
  final String tone;
}

/// Everything a product page shows beyond the menu row. Every part may be empty: the page shows only what the shop filled in.
class ProductInfo {
  ProductInfo({
    this.mrp,
    this.unit,
    this.soldByWeight = false,
    this.warrantyMonths,
    this.prepMinutes,
    this.lowStock,
    this.earliestExpiry,
    this.trackSerials = false,
    this.brand,
    this.badges = const [],
    this.rows = const [],
    this.gallery = const [],
    this.sections = const [],
  });
  final num? mrp;
  final String? unit;
  final bool soldByWeight;
  final int? warrantyMonths;
  final int? prepMinutes;
  final int? lowStock;
  final String? earliestExpiry;
  final bool trackSerials;
  final String? brand;
  final List<ProductBadge> badges;
  final List<({String label, String value})> rows;
  final List<String> gallery;
  final List<DetailSection> sections;

  factory ProductInfo.fromJson(Map<String, dynamic> j) => ProductInfo(
        mrp: j['mrp'] == null ? null : _n(j['mrp']),
        unit: _s(j['unit']),
        soldByWeight: j['soldBy'] == 'weight',
        warrantyMonths: j['warrantyMonths'] == null ? null : _n(j['warrantyMonths']).toInt(),
        prepMinutes: j['prepMinutes'] == null ? null : _n(j['prepMinutes']).toInt(),
        lowStock: j['lowStock'] == null ? null : _n(j['lowStock']).toInt(),
        earliestExpiry: _s(j['earliestExpiry']),
        trackSerials: j['trackSerials'] == true,
        brand: _s(j['brand']),
        badges: [for (final b in ((j['badges'] as List?) ?? const [])) ProductBadge(key: '${(b as Map)['key']}', label: '${b['label']}', tone: '${b['tone']}')],
        rows: [for (final x in ((j['rows'] as List?) ?? const [])) (label: '${(x as Map)['label']}', value: '${x['value']}')],
        gallery: ((j['gallery'] as List?) ?? const []).map((e) => '$e').toList(),
        sections: ((j['sections'] as List?) ?? const []).map((s) => DetailSection.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
      );
}

class MenuItem {
  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.categoryId,
    this.description,
    this.imageUrl,
    this.veg,
    this.available = true,
    this.unavailableLabel,
    this.groups = const [],
    this.bestseller = false,
    this.product,
    this.portion,
  });

  final String id;
  final String name;

  /// The pack size or portion the shop wrote ("500 g", "Serves 2").
  final String? portion;

  /// Photos, specifications and the rest of the product page; null from an older server.
  final ProductInfo? product;

  /// The online base price. Zero for a dish priced through a required choice: use [fromPrice] to show a price.
  final num price;
  final String? categoryId;
  final String? description;
  final String? imageUrl;
  final bool? veg;
  final bool available;
  final String? unavailableLabel;
  final List<ChoiceGroup> groups;

  /// Among the dishes people order most from this shop.
  final bool bestseller;

  bool get hasChoices => groups.isNotEmpty;
  bool get needsChoice => groups.any((g) => g.required);

  /// The lowest the dish can cost: its base plus the cheapest option of every required group.
  num get fromPrice {
    num total = price;
    for (final g in groups.where((g) => g.required)) {
      if (g.options.isEmpty) continue;
      final sorted = g.options.map((o) => o.price).toList()..sort();
      total += sorted.take(g.min > 0 ? g.min : 1).fold<num>(0, (a, b) => a + b);
    }
    return total;
  }

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: '${j['id']}',
        name: '${j['name']}',
        price: _n(j['price']),
        categoryId: _s(j['categoryId']),
        description: _s(j['description']),
        imageUrl: _s(j['imageUrl']),
        veg: j['veg'] is bool ? j['veg'] as bool : null,
        available: j['available'] != false,
        unavailableLabel: _s(j['unavailableLabel']),
        bestseller: j['bestseller'] == true,
        portion: _s(j['portion']),
        product: j['product'] is Map ? ProductInfo.fromJson(Map<String, dynamic>.from(j['product'] as Map)) : null,
        groups: ((j['choiceGroups'] as List?) ?? const []).map((g) => ChoiceGroup.fromJson(Map<String, dynamic>.from(g as Map))).toList(),
      );
}

class MenuCategory {
  MenuCategory({required this.id, required this.name});
  final String id;
  final String name;
  factory MenuCategory.fromJson(Map<String, dynamic> j) => MenuCategory(id: '${j['id']}', name: '${j['name']}');
}

/// An offer a shop is running, as shown on its page.
class ShopOffer {
  ShopOffer({required this.title, this.subtitle, this.code, this.minOrder = 0});
  final String title;
  final String? subtitle;

  /// Set when the customer has to type a code at checkout; null for offers that apply themselves.
  final String? code;
  final num minOrder;

  factory ShopOffer.fromJson(Map<String, dynamic> j) => ShopOffer(
        title: '${j['title']}',
        subtitle: _s(j['subtitle']),
        code: _s(j['code']),
        minOrder: _n(j['minOrder']),
      );
}

class ShopMenu {
  ShopMenu({required this.shop, required this.categories, required this.items, this.offers = const [], this.licences = const [], this.gstin});
  final Shop shop;

  /// The licences Hyperpik has checked for this shop (FSSAI, trade licence...), with when each is valid until.
  final List<({String label, DateTime? validUntil})> licences;
  final String? gstin;
  final List<ShopOffer> offers;
  final List<MenuCategory> categories;
  final List<MenuItem> items;

  factory ShopMenu.fromJson(Map<String, dynamic> j) => ShopMenu(
        shop: Shop.fromJson(Map<String, dynamic>.from(j['shop'] as Map)),
        offers: ((j['offers'] as List?) ?? const []).map((o) => ShopOffer.fromJson(Map<String, dynamic>.from(o as Map))).toList(),
        categories: ((j['categories'] as List?) ?? const []).map((c) => MenuCategory.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
        items: ((j['items'] as List?) ?? const []).map((i) => MenuItem.fromJson(Map<String, dynamic>.from(i as Map))).toList(),
        licences: [
          for (final l in ((j['licences'] as List?) ?? const []))
            (label: '${(l as Map)['label']}', validUntil: l['validUntil'] == null ? null : DateTime.tryParse('${l['validUntil']}')),
        ],
        gstin: _s(j['gstin']),
      );
}

class PopularDish {
  PopularDish({required this.id, required this.name, required this.price, required this.shopHandle, required this.shopName, required this.orders});
  final String id;
  final String name;
  final num price;
  final String shopHandle;
  final String shopName;
  final int orders;

  factory PopularDish.fromJson(Map<String, dynamic> j) => PopularDish(
        id: '${j['id']}',
        name: '${j['name']}',
        price: _n(j['price']),
        shopHandle: '${j['shopHandle']}',
        shopName: '${j['shopName']}',
        orders: _n(j['orders']).toInt(),
      );
}

/// A dish or product people are buying, with the shop that sells it: one card in a "Trending near you" row.
class TrendingItem {
  TrendingItem({
    this.categoryKey = '',
    this.shopId = '',
    required this.id,
    required this.name,
    required this.price,
    required this.fromPrice,
    required this.imageUrl,
    required this.veg,
    required this.hasChoices,
    required this.orders,
    required this.shopHandle,
    required this.shopName,
    required this.shopOpen,
    required this.inRange,
    required this.distanceKm,
  });
  final String categoryKey;
  final String shopId;
  final String id;
  final String name;
  final num price;
  final bool fromPrice;
  final String? imageUrl;
  final bool? veg;
  final bool hasChoices;
  final int orders;
  final String shopHandle;
  final String shopName;
  final bool shopOpen;
  final bool inRange;
  final double? distanceKm;

  bool get canOrder => shopOpen && inRange;

  factory TrendingItem.fromJson(Map<String, dynamic> j) => TrendingItem(
        categoryKey: '${j['categoryKey'] ?? ''}',
        shopId: '${j['shopId'] ?? ''}',
        id: '${j['id']}',
        name: '${j['name']}',
        price: _n(j['price']),
        fromPrice: j['fromPrice'] == true,
        imageUrl: j['imageUrl'] as String?,
        veg: j['veg'] is bool ? j['veg'] as bool : null,
        hasChoices: j['hasChoices'] == true,
        orders: _n(j['orders']).toInt(),
        shopHandle: '${j['shopHandle']}',
        shopName: '${j['shopName']}',
        shopOpen: j['shopOpen'] != false,
        inRange: j['inRange'] != false,
        distanceKm: j['distanceKm'] == null ? null : _n(j['distanceKm']).toDouble(),
      );
}

/// One category's row of trending items.
class TrendingRow {
  TrendingRow({required this.category, required this.items});
  final Category category;
  final List<TrendingItem> items;

  factory TrendingRow.fromJson(Map<String, dynamic> j) => TrendingRow(
        category: Category.fromJson(Map<String, dynamic>.from(j['category'] as Map)),
        items: ((j['items'] as List?) ?? const []).map((i) => TrendingItem.fromJson(Map<String, dynamic>.from(i as Map))).toList(),
      );
}

class HomeData {
  HomeData({required this.categories, required this.promos, required this.shops, this.popular = const [], this.trending = const [], this.dishes = const [], this.orderAgain = const [], this.orderAgainItems = const [], this.catalog = const []});
  final List<Category> categories;
  final List<Promo> promos;
  final List<Shop> shops;
  final List<PopularDish> popular;
  final List<TrendingRow> trending;

  /// Dishes matching the search text, with the shop that sells each.
  final List<TrendingItem> dishes;

  /// Every category that exists, with how many shops are live in each (the home grid shows them all).
  final List<Category> catalog;


  /// Shop ids the customer has ordered from before, most recent first.
  final List<String> orderAgain;

  /// Dishes they have ordered before, at today's prices.
  final List<TrendingItem> orderAgainItems;

  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
        categories: ((j['categories'] as List?) ?? const []).map((c) => Category.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
        promos: ((j['promos'] as List?) ?? const []).map((p) => Promo.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
        shops: ((j['shops'] as List?) ?? const []).map((s) => Shop.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
        popular: ((j['popular'] as List?) ?? const []).map((p) => PopularDish.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
        catalog: ((j['catalog'] as List?) ?? const []).map((c) => Category.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
        orderAgainItems: ((j['orderAgainItems'] as List?) ?? const []).map((i) => TrendingItem.fromJson(Map<String, dynamic>.from(i as Map))).toList(),
        orderAgain: ((j['orderAgain'] as List?) ?? const []).map((e) => '$e').toList(),
        dishes: ((j['dishes'] as List?) ?? const []).map((i) => TrendingItem.fromJson(Map<String, dynamic>.from(i as Map))).toList(),
        trending: ((j['trending'] as List?) ?? const []).map((r) => TrendingRow.fromJson(Map<String, dynamic>.from(r as Map))).toList(),
      );
}
