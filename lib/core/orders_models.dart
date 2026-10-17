// Addresses, quotes and orders as /api/customer/* returns them.

num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
String? _s(Object? v) => v == null ? null : '$v';

class Address {
  Address({
    required this.id,
    required this.label,
    required this.fullAddress,
    this.type = 'home',
    this.landmark,
    this.city,
    this.pincode,
    this.lat,
    this.lng,
    this.isDefault = false,
    this.contactPhone,
    this.contactName,
  });

  final String id;
  final String label;
  final String fullAddress;

  /// Who to ring for a delivery here, when it is not the account holder.
  final String? contactPhone;
  final String? contactName;
  final String type;
  final String? landmark;
  final String? city;
  final String? pincode;
  final double? lat;
  final double? lng;
  final bool isDefault;

  /// Delivery is priced and range-checked from the map position, so an address without one cannot be ordered to.
  bool get hasLocation => lat != null && lng != null;

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: '${j['id']}',
        label: '${j['label'] ?? 'Home'}',
        fullAddress: '${j['fullAddress'] ?? ''}',
        type: '${j['type'] ?? 'home'}',
        landmark: _s(j['landmark']),
        city: _s(j['city']),
        pincode: _s(j['pincode']),
        lat: j['lat'] == null ? null : _n(j['lat']).toDouble(),
        lng: j['lng'] == null ? null : _n(j['lng']).toDouble(),
        isDefault: j['isDefault'] == true,
        contactPhone: _s(j['contactPhone']),
        contactName: _s(j['contactName']),
      );
}

class Quote {
  Quote({
    required this.subtotal,
    required this.deliveryFee,
    required this.tax,
    required this.packing,
    required this.handling,
    required this.paymentFee,
    required this.discount,
    required this.total,
    this.pickupOffered = true,
    this.pickupShop,
    this.pickupAddress,
    this.handlingWaived = false,
    this.handlingSaved = 0,
    this.handlingWaivedText,
    this.deliveryGross = 0,
    this.deliveryVendorPays = 0,
    this.etaNote,
  });

  /// The handling fee is waived: the bill strikes through what it would have been.
  final bool handlingWaived;
  final num handlingSaved;
  final String? handlingWaivedText;

  /// The courier fee before the shop's own subsidy, and how much of it the shop covers.
  final num deliveryGross;
  final num deliveryVendorPays;

  /// Where the delivery fee came from ("for your address"), when the server says.
  final String? etaNote;

  /// Whether the shop lets customers collect an order themselves, and where from.
  final bool pickupOffered;
  final String? pickupShop;
  final String? pickupAddress;
  final num subtotal;
  final num deliveryFee;
  final num tax;
  final num packing;
  final num handling;
  final num paymentFee;
  final num discount;
  final num total;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        subtotal: _n(j['subtotal']),
        deliveryFee: _n(j['deliveryFee']),
        tax: _n(j['tax']),
        packing: _n(j['packing']),
        handling: _n(j['handling']),
        paymentFee: _n(j['paymentFee']),
        discount: _n(j['discount']),
        total: _n(j['total']),
        pickupOffered: (j['pickup'] as Map?)?['offered'] != false,
        pickupShop: _s((j['pickup'] as Map?)?['shop']),
        pickupAddress: _s((j['pickup'] as Map?)?['address']),
        handlingWaived: j['handlingWaived'] == true,
        handlingSaved: _n(j['handlingSaved']),
        handlingWaivedText: _s(j['handlingWaivedText']),
        deliveryGross: _n(j['deliveryGross']),
        deliveryVendorPays: _n(j['deliveryVendorPays']),
        etaNote: _s(j['etaNote']),
      );
}

/// What /api/customer/checkout returns. Online payments carry what Razorpay needs to open.
class PlacedOrder {
  PlacedOrder({required this.orderId, required this.orderNumber, required this.online, this.razorpayOrderId, this.amountPaise, this.keyId, this.dummy = false});
  final String orderId;
  final String orderNumber;
  final bool online;
  final String? razorpayOrderId;
  final int? amountPaise;
  final String? keyId;
  final bool dummy;

  factory PlacedOrder.fromJson(Map<String, dynamic> j) => PlacedOrder(
        orderId: '${j['orderId']}',
        orderNumber: '${j['orderNumber']}',
        online: j['paymentMethod'] == 'razorpay',
        razorpayOrderId: _s(j['razorpayOrderId']),
        amountPaise: j['amount'] == null ? null : _n(j['amount']).toInt(),
        keyId: _s(j['keyId']),
        dummy: j['dummy'] == true,
      );
}

class OrderSummary {
  OrderSummary({required this.id, required this.number, required this.shopName, required this.total, required this.status, required this.paymentStatus, required this.createdAt, this.shopImageUrl, this.refundAmount});
  final String id;
  final String number;
  final String shopName;
  final String? shopImageUrl;
  final num total;
  final String status;
  final String paymentStatus;
  final DateTime createdAt;
  final num? refundAmount;

  bool get isActive => const {'placed', 'accepted', 'processing', 'ready_for_pickup', 'out_for_delivery'}.contains(status);

  factory OrderSummary.fromJson(Map<String, dynamic> j) => OrderSummary(
        id: '${j['id']}',
        number: '${j['number']}',
        shopName: '${j['shopName'] ?? ''}',
        shopImageUrl: _s(j['shopImageUrl']),
        total: _n(j['total']),
        status: '${j['status']}',
        paymentStatus: '${j['paymentStatus']}',
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
        refundAmount: j['refundAmount'] == null ? null : _n(j['refundAmount']),
      );
}

class OrderStep {
  OrderStep({required this.label, required this.reached, this.at});
  final String label;
  final bool reached;
  final DateTime? at;
}

class RefundStep {
  RefundStep({required this.label, required this.detail, required this.state, this.at});
  final String label;
  final String detail;

  /// done, current or todo.
  final String state;
  final DateTime? at;
}

class RefundInfo {
  RefundInfo({required this.state, required this.headline, required this.summary, required this.amount, required this.steps, this.kept, this.overdue = false, this.arn});
  final String state;
  final String headline;
  final String summary;
  final num amount;
  final String? kept;
  final bool overdue;
  final List<RefundStep> steps;
  final String? arn;

  bool get needsAttention => state == 'failed' || state == 'delayed';

  factory RefundInfo.fromJson(Map<String, dynamic> j) {
    final lines = (j['lines'] as List?) ?? const [];
    final arn = lines.map((l) => (l as Map)['arn']).whereType<String>().toList();
    return RefundInfo(
      state: '${j['state']}',
      headline: '${j['headline']}',
      summary: '${j['summary']}',
      amount: _n(j['amount']),
      kept: _s(j['kept']),
      overdue: j['overdue'] == true,
      arn: arn.isEmpty ? null : arn.join(', '),
      steps: ((j['steps'] as List?) ?? const [])
          .map((s) => RefundStep(
                label: '${(s as Map)['label']}',
                detail: '${s['detail']}',
                state: '${s['state']}',
                at: s['at'] == null ? null : DateTime.tryParse('${s['at']}')?.toLocal(),
              ))
          .toList(),
    );
  }
}

class OrderItemLine {
  OrderItemLine({required this.name, required this.quantity, required this.lineTotal, this.variation, this.addons = const []});
  final String name;
  final int quantity;
  final num lineTotal;
  final String? variation;
  final List<String> addons;
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.number,
    required this.status,
    required this.shopName,
    required this.total,
    required this.items,
    required this.steps,
    required this.createdAt,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.canCancel,
    required this.bill,
    this.cannotCancelReason,
    this.addressLabel,
    this.addressFull,
    this.riderName,
    this.riderPhone,
    this.deliveryOtp,
    this.eta,
    this.estimateFrom,
    this.estimateTo,
    this.estimateBasis,
    this.cancelledLabel,
    this.cancelledDetail,
    this.refund,
    this.canReview = false,
    this.reviewRating,
    this.reviewComment,
    this.shopLat,
    this.shopLng,
    this.dropLat,
    this.dropLng,
    this.riderLat,
    this.riderLng,
    this.isPickup = false,
    this.isDineIn = false,
    this.tableLabel,
    this.pickupCode,
    this.pickupShopName,
    this.pickupAddress,
    this.pickupPhone,
    this.pickupLat,
    this.pickupLng,
    this.pickupPrepMinutes,
    this.amountDue = 0,
  });

  /// A pickup order: the customer collects it, so there is no rider, no map and no delivery code.
  final bool isPickup;

  /// A table order (placed by QR code at the shop): no rider, address or delivery code either. Its status stays open while the table eats.
  final bool isDineIn;
  final String? tableLabel;
  final String? pickupCode;
  final String? pickupShopName;
  final String? pickupAddress;
  final String? pickupPhone;
  final double? pickupLat;
  final double? pickupLng;
  final int? pickupPrepMinutes;

  /// Rupees still to pay at the counter (cash on pickup); 0 when it was paid online.
  final num amountDue;
  final bool canReview;
  final int? reviewRating;
  final String? reviewComment;
  final double? shopLat;
  final double? shopLng;
  final double? dropLat;
  final double? dropLng;
  final double? riderLat;
  final double? riderLng;
  final String id;
  final String number;
  final String status;
  final String shopName;
  final num total;
  final DateTime createdAt;
  final String paymentMethod;
  final String paymentStatus;
  final bool canCancel;
  final String? cannotCancelReason;
  final String? addressLabel;
  final String? addressFull;
  final String? riderName;
  final String? riderPhone;
  final String? deliveryOtp;
  final String? eta;

  /// The arrival window worked out on the server (null once delivered or cancelled).
  final DateTime? estimateFrom;
  final DateTime? estimateTo;
  final String? estimateBasis;
  final String? cancelledLabel;
  final String? cancelledDetail;
  final RefundInfo? refund;
  final List<OrderItemLine> items;
  final List<OrderStep> steps;
  final Map<String, num> bill;

  bool get isCancelled => status == 'cancelled';
  bool get isActive => const {'placed', 'accepted', 'processing', 'ready_for_pickup', 'out_for_delivery'}.contains(status) || (isDineIn && status == 'open');

  factory OrderDetail.fromJson(Map<String, dynamic> j) {
    final pickup = j['pickup'] as Map?;
    final pickupShop = pickup?['shop'] as Map?;
    final cancelled = (j['cancelled'] as List?) ?? const [];
    final last = cancelled.isEmpty ? null : cancelled.last as Map;
    final rider = j['rider'] as Map?;
    final bill = <String, num>{for (final e in ((j['bill'] as Map?) ?? const {}).entries) '${e.key}': _n(e.value)};
    return OrderDetail(
      id: '${j['id']}',
      number: '${j['number']}',
      status: '${j['status']}',
      shopName: '${(j['shop'] as Map?)?['name'] ?? ''}',
      total: bill['total'] ?? 0,
      createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      paymentMethod: '${(j['payment'] as Map?)?['method'] ?? ''}',
      paymentStatus: '${(j['payment'] as Map?)?['status'] ?? ''}',
      canCancel: j['canCancel'] == true,
      cannotCancelReason: _s(j['cannotCancelReason']),
      addressLabel: _s((j['address'] as Map?)?['label']),
      addressFull: _s((j['address'] as Map?)?['fullAddress']),
      riderName: _s(rider?['name']),
      riderPhone: _s(rider?['phone']),
      deliveryOtp: _s(j['deliveryOtp']),
      eta: _s(j['eta']),
      estimateFrom: DateTime.tryParse('${(j['estimate'] as Map?)?['from']}')?.toLocal(),
      estimateTo: DateTime.tryParse('${(j['estimate'] as Map?)?['to']}')?.toLocal(),
      estimateBasis: _s((j['estimate'] as Map?)?['basis']),
      cancelledLabel: last == null ? null : _s(last['label']),
      cancelledDetail: last == null ? null : _s(last['detail']),
      refund: j['refund'] == null ? null : RefundInfo.fromJson(Map<String, dynamic>.from(j['refund'] as Map)),
      canReview: j['canReview'] == true,
      reviewRating: (j['review'] as Map?)?['rating'] == null ? null : _n((j['review'] as Map)['rating']).toInt(),
      reviewComment: _s((j['review'] as Map?)?['comment']),
      shopLat: (j['shopLocation'] as Map?)?['lat'] == null ? null : _n((j['shopLocation'] as Map)['lat']).toDouble(),
      shopLng: (j['shopLocation'] as Map?)?['lng'] == null ? null : _n((j['shopLocation'] as Map)['lng']).toDouble(),
      dropLat: (j['dropLocation'] as Map?)?['lat'] == null ? null : _n((j['dropLocation'] as Map)['lat']).toDouble(),
      dropLng: (j['dropLocation'] as Map?)?['lng'] == null ? null : _n((j['dropLocation'] as Map)['lng']).toDouble(),
      riderLat: rider?['lat'] == null ? null : _n(rider!['lat']).toDouble(),
      riderLng: rider?['lng'] == null ? null : _n(rider!['lng']).toDouble(),
      isPickup: j['fulfilment'] == 'pickup',
      isDineIn: j['fulfilment'] == 'dine_in',
      tableLabel: _s(j['tableLabel']),
      pickupCode: _s(pickup?['code']),
      pickupShopName: _s(pickupShop?['name']),
      pickupAddress: _s(pickupShop?['address']),
      pickupPhone: _s(pickupShop?['phone']),
      pickupLat: pickupShop?['lat'] == null ? null : _n(pickupShop!['lat']).toDouble(),
      pickupLng: pickupShop?['lng'] == null ? null : _n(pickupShop!['lng']).toDouble(),
      pickupPrepMinutes: pickup?['prepMinutes'] == null ? null : _n(pickup!['prepMinutes']).toInt(),
      amountDue: _n(pickup?['amountDue'] ?? j['amountDue']),
      bill: bill,
      items: ((j['items'] as List?) ?? const [])
          .map((i) => OrderItemLine(
                name: '${(i as Map)['name']}',
                quantity: _n(i['quantity']).toInt(),
                lineTotal: _n(i['lineTotal']),
                variation: _s(i['variation']),
                addons: ((i['addons'] as List?) ?? const []).map((a) => '$a').toList(),
              ))
          .toList(),
      steps: ((j['steps'] as List?) ?? const [])
          .map((s) => OrderStep(label: '${(s as Map)['label']}', reached: s['reached'] == true, at: s['at'] == null ? null : DateTime.tryParse('${s['at']}')?.toLocal()))
          .toList(),
    );
  }
}

class PlaceHit {
  PlaceHit({required this.primary, required this.secondary, required this.lat, required this.lng, this.full, this.pincode, this.city});
  final String primary;
  final String secondary;
  final double lat;
  final double lng;
  final String? full;
  final String? pincode;
  final String? city;

  factory PlaceHit.fromJson(Map<String, dynamic> j) => PlaceHit(
        primary: '${j['primary'] ?? ''}',
        secondary: '${j['secondary'] ?? ''}',
        lat: _n(j['lat']).toDouble(),
        lng: _n(j['lng']).toDouble(),
        full: _s(j['full']),
        pincode: _s(j['pincode']),
        city: _s(j['city']),
      );
}

class OfferInfo {
  OfferInfo({required this.title, required this.eligible, this.subtitle, this.reason, this.discount = 0, this.freeDelivery = false, this.code, this.couponId});
  final String? couponId;
  final String title;
  final String? subtitle;
  final bool eligible;
  final String? reason;
  final num discount;
  final bool freeDelivery;
  final String? code;

  factory OfferInfo.fromJson(Map<String, dynamic> j) => OfferInfo(
        title: '${j['title']}',
        subtitle: _s(j['subtitle']),
        eligible: j['eligible'] == true,
        reason: _s(j['reason']),
        discount: _n(j['discount']),
        freeDelivery: j['freeDelivery'] == true,
        code: _s(j['code']),
        couponId: _s(j['couponId']),
      );
}

class AppNotification {
  AppNotification({required this.id, required this.title, required this.read, required this.at, this.body, this.href});
  final String id;
  final String title;
  final String? body;
  final String? href;
  final bool read;
  final DateTime at;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: '${j['id']}',
        title: '${j['title']}',
        body: _s(j['body']),
        href: _s(j['href']),
        read: j['read'] == true,
        at: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now(),
      );
}

class IssueOption {
  IssueOption({required this.key, required this.label, this.needsItem = false, this.itemPrompt});
  final String key;
  final String label;
  final bool needsItem;
  final String? itemPrompt;
}

class IssueGroup {
  IssueGroup({required this.category, required this.label, required this.options});
  final String category;
  final String label;
  final List<IssueOption> options;
}

class IssueOptions {
  IssueOptions({required this.groups, required this.items});
  final List<IssueGroup> groups;
  final List<String> items;

  factory IssueOptions.fromJson(Map<String, dynamic> j) => IssueOptions(
        items: ((j['items'] as List?) ?? const []).map((e) => '$e').toList(),
        groups: ((j['groups'] as List?) ?? const [])
            .map((g) => IssueGroup(
                  category: '${(g as Map)['category']}',
                  label: '${g['label']}',
                  options: ((g['options'] as List?) ?? const [])
                      .map((o) => IssueOption(key: '${(o as Map)['key']}', label: '${o['label']}', needsItem: o['needsItem'] == true, itemPrompt: _s(o['itemPrompt'])))
                      .toList(),
                ))
            .toList(),
      );
}

/// One row of the customer's Help & support list.
class SupportTicket {
  SupportTicket({required this.id, required this.summary, required this.status, required this.createdAt, this.orderNumber, this.shopName});
  final String id;
  final String summary;
  final String status;
  final String? orderNumber;
  final String? shopName;
  final DateTime createdAt;

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: '${j['id']}',
        summary: '${j['summary'] ?? ''}',
        status: '${j['status']}',
        orderNumber: _s(j['orderNumber']),
        shopName: _s(j['shopName']),
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class SupportMessage {
  SupportMessage({required this.from, required this.kind, required this.at, this.body, this.imageUrl});
  final String from;
  final String kind;
  final String? body;
  final String? imageUrl;
  final DateTime at;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        from: '${j['from']}',
        kind: '${j['kind']}',
        body: _s(j['body']),
        imageUrl: _s(j['imageUrl']),
        at: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now(),
      );
}

/// A ticket with its whole conversation; [canReply] is true once Hyperpik's team has it and it is not closed.
class SupportThread {
  SupportThread({required this.id, required this.summary, required this.status, required this.createdAt, required this.canReply, required this.messages, this.detail, this.resolution, this.orderNumber, this.shopName});
  final String id;
  final String summary;
  final String? detail;
  final String status;
  final String? resolution;
  final String? orderNumber;
  final String? shopName;
  final DateTime createdAt;
  final bool canReply;
  final List<SupportMessage> messages;

  factory SupportThread.fromJson(Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from(j['ticket'] as Map);
    return SupportThread(
      id: '${t['id']}',
      summary: '${t['summary'] ?? ''}',
      detail: _s(t['detail']),
      status: '${t['status']}',
      resolution: _s(t['resolution']),
      orderNumber: _s(t['orderNumber']),
      shopName: _s(t['shopName']),
      createdAt: DateTime.tryParse('${t['createdAt']}')?.toLocal() ?? DateTime.now(),
      canReply: t['canReply'] == true,
      messages: ((j['messages'] as List?) ?? const []).map((m) => SupportMessage.fromJson(Map<String, dynamic>.from(m as Map))).toList(),
    );
  }
}
