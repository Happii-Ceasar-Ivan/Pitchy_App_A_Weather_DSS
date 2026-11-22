import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pitchy_palette.dart';
import '../../shared/widgets/pitchy_top_bar.dart';

/// Settings (F0): Appearance and Credits. Feedback, updates and the other
/// mock-up rows wait for team decisions (see docs/frontend/f0-screen-flow.md).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).theme;
    return Scaffold(
      appBar: const PitchyTopBar(title: 'Settings'),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _SectionHeader('Appearance'),
            RadioGroup<PitchyThemeMode>(
              groupValue: controller.mode,
              onChanged: (m) => controller.setMode(m!),
              child: Column(
                children: [
                  for (final mode in PitchyThemeMode.values)
                    RadioListTile<PitchyThemeMode>(value: mode, title: Text(mode.label)),
                ],
              ),
            ),
            if (controller.mode == PitchyThemeMode.custom) ...[
              _SwatchPicker(
                label: 'Bar colour',
                selected: controller.customShell,
                onSelected: (s) => controller.setCustom(shell: s),
              ),
              _SwatchPicker(
                label: 'Accent colour',
                selected: controller.customAccent,
                onSelected: (s) => controller.setCustom(accent: s),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Warning and safety colours never change, so they stay readable in every theme.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const Divider(),
            const _SectionHeader('About'),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Credits'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(Routes.credits),
            ),
            if (kDebugMode)
              ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('Component states'),
                subtitle: const Text('Debug builds only'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.stateGallery),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: context.palette.inkMuted),
      ),
    ),
  );
}

class _SwatchPicker extends StatelessWidget {
  const _SwatchPicker({required this.label, required this.selected, required this.onSelected});

  final String label;
  final CustomSwatch selected;
  final ValueChanged<CustomSwatch> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in customSwatches)
              Semantics(
                selected: s == selected,
                button: true,
                label: '$label: ${s.name}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onSelected(s),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: AppTheme.minTarget,
                    height: AppTheme.minTarget,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s == selected ? context.palette.ink : context.palette.hairline,
                        width: s == selected ? 3 : AppTheme.hairline,
                      ),
                    ),
                    child: s == selected ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
