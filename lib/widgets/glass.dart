import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final linux = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    final lowCost = compact || linux;
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: compact ? 0.08 : 0.10),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: compact ? 0.075 : 0.10),
            Colors.white.withValues(alpha: compact ? 0.025 : 0.035),
          ],
        ),
        // A large blurred shadow plus a live BackdropFilter was the hottest
        // raster path in the old dashboard. Keep the glass look static.
        boxShadow: lowCost
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: child,
    );

    // Do not isolate live controls in repaint boundaries on Linux software
    // rendering. Some GTK/software-renderer combinations fail to invalidate
    // an isolated layer until the window receives an expose event (such as a
    // resize), making controller-driven updates appear frozen. Avoiding a
    // rounded clip on the same path also avoids a large software clip being
    // rebuilt while Crostini is processing a configure/resize event.
    if (linux) return panel;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.hardEdge,
      child: panel,
    );
  }
}

class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 22});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final linux = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    if (compact || linux) {
      return Icon(icon, size: size, color: const Color(0xFF9C83FF));
    }
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0xFF8A6DFF), Color(0xFF52D9FF), Color(0xFFFF6EC7)],
      ).createShader(rect),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: compact ? -0.3 : -0.7,
                  ),
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
          ),
        ],
      ],
    );
  }
}
