import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/cart_dock.dart';
import '../../core/theme.dart';

/// The website's login page: Google, or a one-time code by WhatsApp / SMS (mobile) or email. Browsing never asks for it; it
/// is reached from the Account tab and at checkout.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.popOnSuccess = false});

  /// Reached from checkout rather than the Account tab: close once the customer is signed in.
  final bool popOnSuccess;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Step { identify, code, name }

class _SignInScreenState extends State<SignInScreen> with HidesCartDock {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  _Step _step = _Step.identify;
  bool _emailMethod = false;
  bool _sentBySms = false;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _code.addListener(() {
      setState(() {});
      if (_code.text.length == 6 && !_busy && _step == _Step.code) _verify();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _email.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else if (mounted) {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send({bool? sms}) => _run(() async {
        final bySms = sms ?? _sentBySms;
        if (_emailMethod) {
          final e = _email.text.trim();
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
            setState(() => _error = 'Enter a valid email address.');
            return;
          }
          await Api.sendEmailOtp(e);
        } else {
          final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 10) {
            setState(() => _error = 'Enter a valid 10-digit mobile number.');
            return;
          }
          await Api.sendPhoneOtp(_phone.text, sms: bySms);
        }
        if (!mounted) return;
        setState(() {
          _sentBySms = bySms;
          _step = _Step.code;
          _code.clear();
        });
        _startCooldown();
      });

  Future<void> _verify() => _run(() async {
        if (_code.text.trim().length < 4) {
          setState(() => _error = 'Enter the code you received.');
          return;
        }
        if (_emailMethod) {
          await Api.verifyEmailOtp(_email.text.trim(), _code.text);
        } else {
          await Api.verifyPhoneOtp(_phone.text, _code.text);
        }
        HapticFeedback.mediumImpact();
        // A code sign-in has no name to take from a provider: ask once, if there is none yet.
        String name = '';
        try {
          name = '${(await Api.profile())['name'] ?? ''}'.trim();
        } catch (_) {}
        if (name.isEmpty && mounted) {
          setState(() => _step = _Step.name);
          return;
        }
        _finish();
      });

  Future<void> _saveName() => _run(() async {
        if (_name.text.trim().isEmpty) {
          setState(() => _error = 'Enter your name.');
          return;
        }
        await Api.saveProfile(name: _name.text.trim());
        _finish();
      });

  void _finish() {
    if (widget.popOnSuccess && mounted) Navigator.of(context).pop();
  }

  // ---- pieces ----------------------------------------------------------------------------------------------------

  InputDecoration _field(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      );

  Widget _label(String t, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        child,
      ]);

  Widget _link(String text, VoidCallback? onTap, {Color? color, FontWeight weight = FontWeight.w500}) => Center(
        child: InkWell(
          onTap: onTap,
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: weight, color: onTap == null ? Hp.muted(context) : (color ?? Hp.accent))),
        ),
      );

  Widget _primary(String text, VoidCallback? onTap) => SizedBox(width: double.infinity, height: 44, child: FilledButton(onPressed: onTap, child: Text(text)));

  Widget _errorLine() => _error == null ? const SizedBox.shrink() : Text(_error!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad));

  Widget _identify() {
    final muted = Hp.muted(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 46,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Hp.text(context), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), backgroundColor: Hp.surface(context)),
          onPressed: _busy ? null : () => _run(Api.signInWithGoogle),
          icon: const _GoogleMark(),
          label: const Text('Continue with Google'),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Container(height: 1, color: Hp.line(context))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context)))),
        Expanded(child: Container(height: 1, color: Hp.line(context))),
      ]),
      const SizedBox(height: 16),
      Container(
        height: 42,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: Hp.line(context), width: 0.8)),
        child: Row(children: [
          for (final m in const [(false, 'Mobile'), (true, 'Email')])
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() {
                  _emailMethod = m.$1;
                  _error = null;
                }),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _emailMethod == m.$1 ? Hp.accent : null, borderRadius: BorderRadius.circular(999)),
                  child: Text(m.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _emailMethod == m.$1 ? Colors.white : muted)),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      if (!_emailMethod)
        _label(
          'Mobile number',
          Container(
            height: 42,
            decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context), width: 0.8)),
            clipBehavior: Clip.antiAlias,
            child: Row(children: [
              Container(width: 50, alignment: Alignment.center, color: Hp.surface2(context), child: Text('+91', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: muted))),
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')), LengthLimitingTextInputFormatter(14)],
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, hintText: '98765 43210', hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  onSubmitted: (_) => _send(sms: false),
                ),
              ),
            ]),
          ),
        )
      else
        _label('Email address', TextField(controller: _email, keyboardType: TextInputType.emailAddress, style: const TextStyle(fontSize: 14), decoration: _field('you@example.com'), onSubmitted: (_) => _send())),
      if (_error != null) ...[const SizedBox(height: 16), _errorLine()],
      const SizedBox(height: 16),
      _primary(_busy ? 'Sending…' : (_emailMethod ? 'Send code' : 'Send code on WhatsApp'), _busy || _cooldown > 0 ? null : () => _send(sms: false)),
      if (!_emailMethod) ...[const SizedBox(height: 16), _link('No WhatsApp? Send via SMS instead', _busy ? null : () => _send(sms: true))],
    ]);
  }

  Widget _codeStep() {
    final to = _emailMethod ? _email.text.trim() : '+91 ${_phone.text.trim()}';
    final how = _emailMethod ? 'Code sent to ' : (_sentBySms ? 'Code sent by SMS to ' : 'Code sent on WhatsApp to ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$how$to.', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
      const SizedBox(height: 16),
      _label(
        '6-digit code',
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: const TextStyle(fontSize: 18, letterSpacing: 7.2),
          decoration: _field('123456').copyWith(hintStyle: TextStyle(fontSize: 18, letterSpacing: 7.2, color: Hp.faint(context))),
        ),
      ),
      if (_error != null) ...[const SizedBox(height: 16), _errorLine()],
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _busy ? null : _verify, child: Text(_busy ? 'Verifying…' : 'Verify & continue'))),
      const SizedBox(height: 16),
      _link(_cooldown > 0 ? 'Resend in ${_cooldown}s' : (_emailMethod ? 'Resend code' : (_sentBySms ? 'Resend code via SMS' : 'Resend code on WhatsApp')), _busy || _cooldown > 0 ? null : () => _send()),
      if (!_emailMethod && _cooldown <= 0) ...[
        const SizedBox(height: 16),
        _link(_sentBySms ? 'Send on WhatsApp instead' : 'No WhatsApp? Send via SMS instead', _busy ? null : () => _send(sms: !_sentBySms)),
      ],
      const SizedBox(height: 16),
      _link(_emailMethod ? 'Use a different email' : 'Use a different number', () => setState(() {
            _step = _Step.identify;
            _code.clear();
            _error = null;
          }), color: Hp.muted(context), weight: FontWeight.w500),
    ]);
  }

  Widget _nameStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('You’re in. What should we call you?', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
        const SizedBox(height: 16),
        _label('Your name', TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, style: const TextStyle(fontSize: 14), decoration: _field('e.g. Priya Sharma'))),
        if (_error != null) ...[const SizedBox(height: 16), _errorLine()],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _busy ? null : _saveName, child: Text(_busy ? 'Saving…' : 'Continue'))),
      ]);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Hp.page(context),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, top + (widget.popOnSuccess ? 16 : 64), 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.popOnSuccess)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_back_rounded, size: 16, color: Hp.muted(context)),
                  const SizedBox(width: 6),
                  Text('Back', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
                ]),
              ),
            ),
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.asset('assets/brand/logo.png', width: 32, height: 32)),
            const SizedBox(width: 8),
            const Text('hyperpik', style: TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Hp.accent)),
          ]),
          const SizedBox(height: 32),
          const Text('Welcome back', style: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.75)),
          const SizedBox(height: 8),
          Text('We’ll text you a one-time code — no password to remember.', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context).withValues(alpha: 0.8), width: 0.8)),
            child: switch (_step) {
              _Step.identify => _identify(),
              _Step.code => _codeStep(),
              _Step.name => _nameStep(),
            },
          ),
          const SizedBox(height: 24),
          Text('By continuing you agree to our Terms of use and Privacy policy.', style: TextStyle(fontSize: 13, height: 1.4, color: Hp.faint(context))),
        ]),
      ),
    );
  }
}

/// Google's four-colour G, drawn inline so nothing has to be downloaded.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 17, height: 17, child: CustomPaint(painter: _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final stroke = size.width * 0.22;
    final rect = Rect.fromCircle(center: c, radius: r - stroke / 2);
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Arcs in the order of the logo: red top, yellow left, green bottom, blue right.
    canvas.drawArc(rect, -2.5, 1.1, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, 2.3, 1.2, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 0.75, 1.55, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, -0.85, 1.55, false, p(const Color(0xFF4285F4)));
    canvas.drawLine(Offset(r, r), Offset(size.width - 1, r), Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
