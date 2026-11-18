import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// What an item without a photo shows: its own name on a plain tile. A stock picture here would be a promise about the
/// food (a pizza standing in for a fish dish), so nothing is drawn that the shop did not provide. A thumbnail too small
/// to read the name shows its initials instead. Mirrors components/ui/item-photo.tsx on the website.
class NameTile extends StatelessWidget {
  const NameTile({super.key, required this.name});

  final String name;

  static String initialsOf(String name) {
    final words = RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(name).map((m) => m.group(0)!).take(2);
    final out = words.map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
    return out.isEmpty ? '?' : out;
  }

  @override
  Widget build(BuildContext context) {
    final ink = Hp.isDark(context) ? const Color(0xFFA78BFA) : const Color(0xFF4C1AD4);
    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: ColoredBox(
        color: Hp.tint(context),
        child: LayoutBuilder(builder: (context, box) {
          final width = box.maxWidth.isFinite ? box.maxWidth : 112.0;
          final small = width < 88;
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: width * 0.08),
              child: Text(
                small ? initialsOf(name) : name,
                maxLines: small ? 1 : 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  height: small ? 1 : 1.2,
                  fontSize: small ? (width * 0.34).clamp(13.0, 20.0) : (width * 0.11).clamp(12.0, 28.0),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// An item's own photo, or its name tile when it has none or the photo cannot be loaded.
class ItemPhoto extends StatelessWidget {
  const ItemPhoto({super.key, required this.url, required this.name, this.fit = BoxFit.cover});

  final String? url;
  final String name;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final src = (url ?? '').trim();
    if (src.isEmpty) return NameTile(name: name);
    return CachedNetworkImage(
      imageUrl: src,
      fit: fit,
      placeholder: (_, __) => ColoredBox(color: Hp.surface2(context)),
      errorWidget: (_, __, ___) => NameTile(name: name),
    );
  }
}
