import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';

/// "Book a table" for one shop: a date, a time, how many people, who the booking is for. The shop confirms or declines.
class ReserveScreen extends StatefulWidget {
  const ReserveScreen({super.key, required this.shop});
  final Shop shop;

  @override
  State<ReserveScreen> createState() => _ReserveScreenState();
}

class _ReserveScreenState extends State<ReserveScreen> {
  DateTime? _date;
  TimeOfDay? _time;
  int _party = 2;
  late final TextEditingController _name = TextEditingController(text: '${Api.user?.userMetadata?['full_name'] ?? ''}');
  late final TextEditingController _phone = TextEditingController(text: (Api.user?.phone ?? '').length > 10 ? Api.user!.phone!.substring(Api.user!.phone!.length - 10) : (Api.user?.phone ?? ''));
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date ?? now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 20, minute: 0));
    if (t != null) setState(() => _time = t);
  }

  Future<void> _send() async {
    final d = _date;
    final t = _time;
    if (d == null || t == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.reserveTable(
        shopId: widget.shop.id,
        date: '${d.year}-${_two(d.month)}-${_two(d.day)}',
        time: '${_two(t.hour)}:${_two(t.minute)}',
        partySize: _party,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        note: _note.text.trim(),
      );
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final maxParty = shop.reservationMaxParty;
    return Scaffold(
      appBar: AppBar(title: const Text('Book a table')),
      body: _sent
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle_rounded, size: 56, color: Hp.ok),
                const SizedBox(height: 16),
                const Text('Request sent', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('${shop.name} will confirm your table soon. You will get a notification when they do.', textAlign: TextAlign.center, style: TextStyle(color: Hp.muted(context))),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const MyReservationsScreen())), child: const Text('See my bookings')),
              ]),
            )
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text('at ${shop.name}', style: TextStyle(fontSize: 14, color: Hp.muted(context))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_rounded, size: 18), label: Text(_date == null ? 'Date' : '${_date!.day}/${_date!.month}/${_date!.year}'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(_time == null ? 'Time' : _time!.format(context)))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                const Expanded(child: Text('People', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                IconButton(onPressed: _party > 1 ? () => setState(() => _party--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                Text('$_party', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(onPressed: _party < maxParty ? () => setState(() => _party++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
              ]),
              Text('Up to $maxParty people. For a bigger group, please call the shop.', style: TextStyle(fontSize: 12, color: Hp.faint(context))),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name for the booking')),
              const SizedBox(height: 12),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Anything the shop should know (optional)')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Hp.bad))),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy || _date == null || _time == null ? null : _send, child: Text(_busy ? 'Sending…' : 'Request this table')),
              const SizedBox(height: 8),
              Text(shop.reservationNoticeHours > 0 ? 'Please book at least ${shop.reservationNoticeHours} hour${shop.reservationNoticeHours == 1 ? '' : 's'} ahead. The table is held once ${shop.name} confirms it.' : 'The table is held once ${shop.name} confirms it.', style: TextStyle(fontSize: 12, color: Hp.faint(context))),
            ]),
    );
  }
}

/// The customer's own table bookings, with a cancel button while a booking is still open.
class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  List<Reservation>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.myReservations();
      if (mounted) setState(() => _list = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static const _labels = {'requested': 'Waiting for the shop', 'confirmed': 'Confirmed', 'declined': 'Declined', 'cancelled': 'Cancelled', 'seated': 'Seated', 'no_show': 'Did not come'};

  String _when(DateTime d) {
    final l = d.toLocal();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '${days[l.weekday - 1]} ${l.day}/${l.month}, $h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'am' : 'pm'}';
  }

  Future<void> _cancel(Reservation r) async {
    try {
      await Api.cancelReservation(r.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('My table bookings')),
      body: _error != null
          ? Center(child: Text(_error!))
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No bookings yet. Open a shop that takes bookings and tap Book a table.', textAlign: TextAlign.center)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final open = (r.status == 'requested' || r.status == 'confirmed') && r.at.isAfter(DateTime.now());
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: cardDecoration(context),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(r.shopName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                              Text(_labels[r.status] ?? r.status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Hp.muted(context))),
                            ]),
                            const SizedBox(height: 4),
                            Text('${_when(r.at)} · ${r.partySize} ${r.partySize == 1 ? 'person' : 'people'}', style: TextStyle(color: Hp.muted(context))),
                            if (r.shopNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('From the shop: ${r.shopNote}')),
                            if (open) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(onPressed: () => _cancel(r), child: const Text('Cancel booking'))),
                          ]),
                        );
                      },
                    ),
    );
  }
}
