import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Frosted Deep Forest surface for UI floating over the map.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.opacity = 0.68,
    this.blur = 16,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double opacity;
  final double blur;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: AppDecorations.glass(radius: radius, opacity: 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.glassTeal.withValues(alpha: opacity),
                    AppColors.glassDeep.withValues(alpha: opacity),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// Round glass map control.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 44,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => GlassPanel(
        radius: size / 2,
        child: Material(
          type: MaterialType.transparency,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            constraints: BoxConstraints.tightFor(width: size, height: size),
            padding: EdgeInsets.zero,
            style: active
                ? IconButton.styleFrom(
                    backgroundColor: AppColors.mint.withValues(alpha: 0.28))
                : null,
            icon: Icon(icon,
                size: size * 0.46,
                color: onPressed == null
                    ? AppColors.textMuted.withValues(alpha: 0.4)
                    : iconColor ?? (active ? AppColors.white : AppColors.softMint)),
          ),
        ),
      );
}

/// Rounded pill selector with a Mint active segment.
class GlassSegmented<T> extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.icon,
    this.dense = false,
    this.expand = false,
  });

  /// Stretch segments equally across the available width.
  final bool expand;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final IconData Function(T)? icon;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
          for (final v in values)
            if (expand) Expanded(child: _segment(v)) else _segment(v),
        ]),
      );

  Widget _label(T v) => Text(label(v),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: dense ? 12 : 13,
          fontWeight: FontWeight.w600,
          color: v == selected ? AppColors.white : AppColors.softMint));

  Widget _segment(T v) => InkWell(
              onTap: () => onChanged(v),
              borderRadius: BorderRadius.circular(22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                    horizontal: dense ? 12 : 16, vertical: dense ? 7 : 10),
                decoration: BoxDecoration(
                  color: v == selected ? AppColors.mint : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: v == selected
                      ? [
                          BoxShadow(
                              color: AppColors.mint.withValues(alpha: 0.35),
                              blurRadius: 12)
                        ]
                      : null,
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon!(v),
                            size: dense ? 15 : 17,
                            color: v == selected ? AppColors.white : AppColors.softMint),
                        const SizedBox(width: 6),
                      ],
                      if (expand) Flexible(child: _label(v)) else _label(v),
                    ]),
              ),
            );
}

/// Titled inner card used inside glass panels.
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: AppDecorations.card(radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.mint),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title!,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 12),
          ],
          child,
        ]),
      );
}
