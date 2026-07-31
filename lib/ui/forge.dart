import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'digital_librarian.dart';

/// Elevated "Memory Forge" design primitives.
///
/// Built on the Digital Librarian palette but richer: layered ambient
/// backgrounds, panels with depth and corner accents, strong type contrast
/// (Space Grotesk display vs JetBrains Mono metadata), and living status
/// elements. Used across the redesigned Planning, Code Review, Chat and
/// Deep Research surfaces.
abstract final class Forge {
  // --- type ---------------------------------------------------------------
  static TextStyle display(
    BuildContext context, {
    double size = 30,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = -1.1,
    double? height,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle mono(
    BuildContext context, {
    double size = 10,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 1.1,
    Color? color,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color ?? DigitalLibrarian.secondary,
    );
  }

  // --- color helpers ------------------------------------------------------
  static Color withAlpha(Color c, double a) => c.withValues(alpha: a);
}

/// Layered ambient background: fine grid, two soft radial glows and a
/// vignette. Placed behind screen content via a [Stack].
class ForgeBackground extends StatelessWidget {
  const ForgeBackground({
    super.key,
    this.glowOne = DigitalLibrarian.primaryStrong,
    this.glowTwo = DigitalLibrarian.secondary,
    this.child,
  });

  final Color glowOne;
  final Color glowTwo;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ForgeGridPainter()),
        ),
        Positioned(
          top: -140,
          left: -120,
          child: _glow(glowOne, 340),
        ),
        Positioned(
          bottom: -160,
          right: -120,
          child: _glow(glowTwo, 300),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.4,
                colors: [
                  Colors.transparent,
                  Forge.withAlpha(DigitalLibrarian.background, 0.85),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Forge.withAlpha(color, 0.16), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _ForgeGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Forge.withAlpha(DigitalLibrarian.primary, 0.045)
      ..strokeWidth = 1;
    const step = 34.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Elevated panel: layered border, subtle top highlight, optional left
/// accent rail and corner tick. The workhorse surface of the redesign.
class ForgePanel extends StatelessWidget {
  const ForgePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.accent,
    this.onTap,
    this.borderColor,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final VoidCallback? onTap;
  final Color? borderColor;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? Forge.withAlpha(DigitalLibrarian.outline, 0.7);

    final panel = Container(
      margin: margin,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DigitalLibrarian.surfaceContainer,
            DigitalLibrarian.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Forge.withAlpha(Colors.black, 0.4),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // top hairline highlight
          Positioned(
            left: 10,
            right: 10,
            top: -1,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Forge.withAlpha(
                      accent ?? DigitalLibrarian.primary,
                      0.5,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          if (accent != null)
            Positioned(
              left: -1,
              top: 12,
              bottom: 12,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Forge.withAlpha(accent!, 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          child,
        ],
      ),
    );

    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: Forge.withAlpha(DigitalLibrarian.primary, 0.05),
        child: panel,
      ),
    );
  }
}

/// Monospace uppercase micro-label, the "technical annotation" voice.
class ForgeEyebrow extends StatelessWidget {
  const ForgeEyebrow(this.label, {super.key, this.color, this.trailing});

  final String label;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      style: Forge.mono(context, color: color),
    );
    if (trailing == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [text, const SizedBox(width: 8), trailing!],
    );
  }
}

/// Large stat: oversized display number with a mono label beneath.
class ForgeStat extends StatelessWidget {
  const ForgeStat({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.size = 30,
  });

  final String value;
  final String label;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DigitalLibrarian.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Forge.display(context, size: size, color: c, letterSpacing: -1.4),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: Forge.mono(
            context,
            size: 8.5,
            color: Forge.withAlpha(DigitalLibrarian.primary, 0.55),
            letterSpacing: 1.3,
          ),
        ),
      ],
    );
  }
}

/// Pulsing living status dot with a mono label.
class ForgeStatus extends StatefulWidget {
  const ForgeStatus({
    super.key,
    required this.label,
    this.active = true,
    this.color,
  });

  final String label;
  final bool active;
  final Color? color;

  @override
  State<ForgeStatus> createState() => _ForgeStatusState();
}

class _ForgeStatusState extends State<ForgeStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? (widget.color ?? DigitalLibrarian.secondary)
        : Forge.withAlpha(DigitalLibrarian.primary, 0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = widget.active ? _ctrl.value : 0.0;
            return Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: Forge.withAlpha(color, 0.25 + 0.45 * t),
                    blurRadius: 6 + 6 * t,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          widget.label.toUpperCase(),
          style: Forge.mono(context, size: 9, color: color, letterSpacing: 1.2),
        ),
      ],
    );
  }
}

/// Crafted chip with icon + mono-ish label, tinted by [color].
class ForgeChip extends StatelessWidget {
  const ForgeChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DigitalLibrarian.primary;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Forge.withAlpha(c, selected ? 0.2 : 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Forge.withAlpha(c, selected ? 0.65 : 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: chip,
      ),
    );
  }
}

/// Animated progress bar with a glowing head.
class ForgeProgress extends StatelessWidget {
  const ForgeProgress({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double value; // 0..1
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DigitalLibrarian.secondary;
    final v = value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Forge.withAlpha(DigitalLibrarian.surfaceHighest, 0.8),
            borderRadius: BorderRadius.circular(height),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) {
                return FractionallySizedBox(
                  widthFactor: t,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Forge.withAlpha(c, 0.55), c],
                      ),
                      borderRadius: BorderRadius.circular(height),
                      boxShadow: [
                        BoxShadow(
                          color: Forge.withAlpha(c, 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Primary call-to-action button with a soft glow and press feedback.
class ForgeButton extends StatelessWidget {
  const ForgeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = DigitalLibrarian.secondary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final btn = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: disabled ? Forge.withAlpha(color, 0.25) : color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: Forge.withAlpha(color, 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: DigitalLibrarian.background),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: DigitalLibrarian.background,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: btn,
      ),
    );
  }
}

/// Section header: mono eyebrow over a large display title, optional trailing.
class ForgeSectionHeader extends StatelessWidget {
  const ForgeSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
    this.eyebrowColor,
  });

  final String eyebrow;
  final String title;
  final Widget? trailing;
  final Color? eyebrowColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForgeEyebrow(eyebrow, color: eyebrowColor),
              const SizedBox(height: 6),
              Text(
                title,
                style: Forge.display(context, size: 26),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Score ring: animated circular gauge with a centered display number.
class ForgeScoreRing extends StatelessWidget {
  const ForgeScoreRing({
    super.key,
    required this.score,
    this.size = 74,
    this.color,
  });

  final int score;
  final double size;
  final Color? color;

  static Color colorFor(int score) {
    if (score >= 90) return DigitalLibrarian.secondary;
    if (score >= 70) return DigitalLibrarian.primary;
    if (score >= 50) return const Color(0xFFF2B544);
    return const Color(0xFFF27E9D);
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? colorFor(score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              return CircularProgressIndicator(
                value: t,
                strokeWidth: size * 0.09,
                backgroundColor:
                    Forge.withAlpha(DigitalLibrarian.surfaceHighest, 0.9),
                valueColor: AlwaysStoppedAnimation(c),
              );
            },
          ),
          Text(
            '$score',
            style: Forge.display(context, size: size * 0.26, color: c),
          ),
        ],
      ),
    );
  }
}
