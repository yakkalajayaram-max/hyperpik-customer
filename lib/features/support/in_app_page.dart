import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import '../../core/theme.dart';

/// Opens one of the website's public pages (a policy, About, Contact) inside the app, with a back arrow, instead of handing
/// the customer to their browser. The browser is the fallback only where an in-app page cannot be shown.
Future<void> openSitePage(BuildContext context, String title, String path) {
  final url = '${AppConfig.siteUrl}$path';
  if (kIsWeb) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InAppPage(title: title, url: url)));
}

/// The app already has its own header and tab bar, so the website's are hidden, and the page takes the app's theme.
String _embed(bool dark) => '''
(function () {
  document.documentElement.setAttribute('data-theme', '${dark ? 'dark' : 'light'}');
  if (document.getElementById('hp-embed')) return;
  var s = document.createElement('style');
  s.id = 'hp-embed';
  s.textContent = 'body > header, header.sticky, body > footer, footer, nav.fixed, nav[class*="fixed"] { display: none !important; } body { padding-bottom: 24px !important; }';
  document.head.appendChild(s);
})();
''';

class InAppPage extends StatefulWidget {
  const InAppPage({super.key, required this.title, required this.url});
  final String title;
  final String url;

  @override
  State<InAppPage> createState() => _InAppPageState();
}

class _InAppPageState extends State<InAppPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _dark = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (_) => _controller.runJavaScript(_embed(_dark)),
        // Stay inside the website's own pages; anything else (a mailto:, tel:, another site) goes to the phone's own handler.
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri != null && uri.host != Uri.parse(AppConfig.siteUrl).host && uri.scheme != 'about') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dark = Hp.isDark(context);
    _controller.setBackgroundColor(Hp.page(context));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Hp.page(context),
        appBar: AppBar(
          backgroundColor: Hp.surface(context),
          title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          bottom: _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: Hp.accent, backgroundColor: Colors.transparent)) : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
