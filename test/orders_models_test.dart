import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_customer/core/orders_models.dart';

void main() {
  test('a cancelled, refunded order reads back with its refund steps', () {
    final o = OrderDetail.fromJson({
      'id': 'o1',
      'number': 'HP007262',
      'status': 'cancelled',
      'createdAt': '2026-10-14T09:05:40Z',
      'shop': {'name': 'TUMYUM KITCHEN'},
      'payment': {'method': 'razorpay', 'status': 'refunded'},
      'bill': {'subtotal': 120, 'delivery': 65, 'total': 191},
      'items': [
        {'name': 'APRICOT DELIGHT', 'quantity': 1, 'lineTotal': 120}
      ],
      'steps': [
        {'label': 'Order placed', 'reached': true}
      ],
      'cancelled': [
        {'label': "Cancelled — the store didn't respond in time", 'detail': null}
      ],
      'canCancel': false,
      'refund': {
        'state': 'processing',
        'headline': 'Refund of ₹191.00 is being processed',
        'summary': 'On its way.',
        'amount': 191,
        'kept': null,
        'overdue': false,
        'steps': [
          {'label': 'Order cancelled, refund started', 'detail': 'x', 'state': 'done'},
          {'label': 'Sent to your bank', 'detail': 'y', 'state': 'current'},
          {'label': 'In your account', 'detail': 'z', 'state': 'todo'},
        ],
        'lines': [
          {'amount': 191, 'status': 'pending', 'arn': null}
        ],
      },
    });
    expect(o.isCancelled, isTrue);
    expect(o.isActive, isFalse);
    expect(o.total, 191);
    expect(o.refund!.amount, 191);
    expect(o.refund!.needsAttention, isFalse);
    expect(o.refund!.steps.map((s) => s.state), ['done', 'current', 'todo']);
    expect(o.cancelledLabel, contains("didn't respond"));
  });

  test('a failed refund asks for attention', () {
    final r = RefundInfo.fromJson({'state': 'failed', 'headline': 'h', 'summary': 's', 'amount': 50, 'steps': []});
    expect(r.needsAttention, isTrue);
  });

  test('an order is active until it is delivered or cancelled', () {
    OrderSummary s(String status) => OrderSummary.fromJson({'id': 'a', 'number': 'N', 'status': status, 'paymentStatus': 'paid', 'total': 10, 'createdAt': '2026-10-14T09:05:40Z'});
    expect(s('placed').isActive, isTrue);
    expect(s('out_for_delivery').isActive, isTrue);
    expect(s('delivered').isActive, isFalse);
    expect(s('cancelled').isActive, isFalse);
  });

  test('an address without a map position cannot be delivered to', () {
    expect(Address.fromJson({'id': 'a', 'label': 'Home', 'fullAddress': 'x'}).hasLocation, isFalse);
    expect(Address.fromJson({'id': 'a', 'label': 'Home', 'fullAddress': 'x', 'lat': 17.4, 'lng': 78.4}).hasLocation, isTrue);
  });

  test('a quote reads its figures', () {
    final q = Quote.fromJson({'subtotal': 120, 'deliveryFee': 65, 'tax': 6, 'packing': 0, 'handling': 0, 'paymentFee': 0, 'discount': 0, 'total': 191});
    expect(q.total, 191);
    expect(q.deliveryFee, 65);
  });

  test('a delivered order carries its rating and the points for the map', () {
    final o = OrderDetail.fromJson({
      'id': 'o1',
      'number': 'HP1',
      'status': 'delivered',
      'createdAt': '2026-10-14T09:05:40Z',
      'shop': {'name': 'S'},
      'payment': {'method': 'cod', 'status': 'paid'},
      'bill': {'total': 100},
      'items': [],
      'steps': [],
      'canReview': true,
      'review': {'rating': 4, 'comment': 'Good'},
      'shopLocation': {'lat': 17.4, 'lng': 78.4},
      'dropLocation': {'lat': 17.41, 'lng': 78.41},
      'rider': {'name': 'R', 'phone': '9', 'lat': 17.405, 'lng': 78.405},
    });
    expect(o.canReview, isTrue);
    expect(o.reviewRating, 4);
    expect(o.shopLat, 17.4);
    expect(o.dropLng, 78.41);
    expect(o.riderLat, 17.405);
  });

  test('issue options group the ways an order can go wrong', () {
    final i = IssueOptions.fromJson({
      'items': ['Soup'],
      'groups': [
        {
          'category': 'order_wrong',
          'label': 'Something is wrong with the order',
          'options': [
            {'key': 'missing', 'label': 'An item is missing', 'needsItem': true, 'itemPrompt': 'Which item?'},
            {'key': 'someone_else', 'label': 'I got another order', 'needsItem': false},
          ],
        }
      ],
    });
    expect(i.groups.single.options.length, 2);
    expect(i.groups.single.options.first.needsItem, isTrue);
    expect(i.items, ['Soup']);
  });

  test('an offer that cannot be used says why', () {
    final o = OfferInfo.fromJson({'title': 'Flat 50 off', 'eligible': false, 'reason': 'Add 80 more to use this'});
    expect(o.eligible, isFalse);
    expect(o.reason, contains('80'));
  });

  test('an active order carries the arrival window from the server', () {
    final o = OrderDetail.fromJson({
      'id': 'o2',
      'number': 'HP007263',
      'status': 'accepted',
      'createdAt': '2026-10-15T08:08:00Z',
      'shop': {'name': 'TUMYUM KITCHEN'},
      'payment': {'method': 'razorpay', 'status': 'paid'},
      'bill': {'total': 231.95},
      'items': const [],
      'steps': const [],
      'estimate': {'from': '2026-10-15T08:35:00Z', 'to': '2026-10-15T08:45:00Z', 'minutesLeft': 30, 'basis': 'being_prepared'},
    });
    expect(o.estimateFrom, isNotNull);
    expect(o.estimateTo!.difference(o.estimateFrom!).inMinutes, 10);
    expect(o.estimateBasis, 'being_prepared');
  });

  test('a delivered order has no estimate', () {
    final o = OrderDetail.fromJson({
      'id': 'o3',
      'number': 'HP1',
      'status': 'delivered',
      'createdAt': '2026-10-15T08:08:00Z',
      'shop': {'name': 'S'},
      'payment': {'method': 'cod', 'status': 'paid'},
      'bill': {'total': 10},
      'items': const [],
      'steps': const [],
      'estimate': null,
    });
    expect(o.estimateFrom, isNull);
  });
}
