import 'package:material_ui/material_ui.dart';

/// The Pitchy logo. PLACEHOLDER asset until the team supplies the real one
/// (P-14): replace `assets/images/pitchy_logo_placeholder.png` and update [asset].
class PitchyLogo extends StatelessWidget {
  const PitchyLogo({super.key, this.size = 32});

  static const asset = 'assets/images/pitchy_logo_placeholder.png';

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: size,
    height: size,
    semanticLabel: 'Pitchy',
    filterQuality: FilterQuality.medium,
  );
}
