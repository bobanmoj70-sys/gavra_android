import 'package:flutter/material.dart';

/// 🛡️💥 V3SAFETEXT - OVERFLOW PROTECTION DOMINATOR! 💥🛡️
/// Eliminira sve Text overflow probleme u celom codebase-u
/// Automatski safe rendering za user-generated content
class V3SafeText extends StatelessWidget {
  const V3SafeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textScaleFactor,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final double? textScaleFactor;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines ?? 3, // Default safe max lines
      overflow: overflow ?? TextOverflow.ellipsis, // Default safe overflow
      softWrap: softWrap ?? true,
      textScaleFactor: textScaleFactor,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
    );
  }

  // ─── PREDEFINED SAFE TEXT VARIANTS ─────────────────────────────────────────

  /// User imena - 1 linija, ellipsis
  static Widget userName(String name, {TextStyle? style}) {
    return V3SafeText(
      name,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// User adrese - 2 linije, ellipsis
  static Widget userAddress(String address, {TextStyle? style}) {
    return V3SafeText(
      address,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Napomene - 3 linije, ellipsis
  static Widget note(String note, {TextStyle? style}) {
    return V3SafeText(
      note,
      style: style,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Brojevi/counteri - 1 linija, fade overflow
  static Widget counter(String count, {TextStyle? style}) {
    return V3SafeText(
      count,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.fade,
    );
  }

  /// Email/telefon - 1 linija, ellipsis sa middle cutting
  static Widget contact(String contact, {TextStyle? style}) {
    return V3SafeText(
      _formatContact(contact),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Status labels - 1 linija, clip
  static Widget status(String status, {TextStyle? style}) {
    return V3SafeText(
      status,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Dugački opisi - više linija, fade
  static Widget description(String description, {TextStyle? style, int maxLines = 5}) {
    return V3SafeText(
      description,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.fade,
    );
  }

  // ─── HELPER METHODS ────────────────────────────────────────────────────────

  /// Format contact za better middle cutting
  static String _formatContact(String contact) {
    if (contact.isEmpty) return contact;
    if (contact.length <= 20) return contact;

    // Za email: user...@domain.com
    if (contact.contains('@')) {
      final parts = contact.split('@');
      if (parts.length == 2) {
        final user = parts[0];
        final domain = parts[1];
        if (user.length > 10) {
          return '${user.substring(0, 8)}...@$domain';
        }
      }
    }

    // Za telefon: +381...567
    if (contact.startsWith('+') && contact.length > 15) {
      return '${contact.substring(0, 8)}...${contact.substring(contact.length - 3)}';
    }

    return contact;
  }
}

/// 🛡️💥 V3SAFE CONTAINER - OVERFLOW PROTECTION ZA KOMPLEKSNE WIDGETI 💥🛡️
class V3SafeContainer extends StatelessWidget {
  const V3SafeContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.constraints,
    this.padding,
    this.margin,
    this.decoration,
    this.foregroundDecoration,
    this.transform,
    this.transformAlignment,
    this.clipBehavior = Clip.antiAlias, // Default safe clipping
  });

  final Widget child;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Decoration? decoration;
  final Decoration? foregroundDecoration;
  final Matrix4? transform;
  final AlignmentGeometry? transformAlignment;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final hasClipSource = decoration != null || foregroundDecoration != null;
    return Container(
      width: width,
      height: height,
      constraints: constraints,
      padding: padding,
      margin: margin,
      decoration: decoration,
      foregroundDecoration: foregroundDecoration,
      transform: transform,
      transformAlignment: transformAlignment,
      clipBehavior: hasClipSource ? clipBehavior : Clip.none,
      child: child,
    );
  }
}

/// 🛡️💥 V3SAFE ROW/COLUMN - OVERFLOW PROTECTION ZA FLEXIBILE LAYOUTS 💥🛡️
class V3SafeRow extends StatelessWidget {
  const V3SafeRow({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.verticalDirection = VerticalDirection.down,
    this.textBaseline,
    this.scrollable = true,
    this.useIntrinsic = false,
    required this.children,
  });

  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection? textDirection;
  final VerticalDirection verticalDirection;
  final TextBaseline? textBaseline;
  final bool scrollable;
  final bool useIntrinsic;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Widget content = Row(
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: textDirection,
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      children: children,
    );

    if (useIntrinsic) {
      content = IntrinsicHeight(child: content);
    }

    if (!scrollable) {
      return content;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: content,
    );
  }
}

class V3SafeColumn extends StatelessWidget {
  const V3SafeColumn({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.verticalDirection = VerticalDirection.down,
    this.textBaseline,
    this.scrollable = true,
    this.useIntrinsic = false,
    required this.children,
  });

  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection? textDirection;
  final VerticalDirection verticalDirection;
  final TextBaseline? textBaseline;
  final bool scrollable;
  final bool useIntrinsic;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: textDirection,
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      children: children,
    );

    if (useIntrinsic) {
      content = IntrinsicWidth(child: content);
    }

    if (!scrollable) {
      return content;
    }

    return SingleChildScrollView(
      child: content,
    );
  }
}
