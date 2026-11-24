import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_scope.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pitchy_palette.dart';
import '../../shared/services/mock/fixtures.dart' show MockScenario;
import '../../shared/services/mock/mock_pitchy_api.dart';
import '../../shared/widgets/pitchy_top_bar.dart';
import 'update_check.dart';

/// Full Settings (P-16, P-17). Rows whose content the team hasn't supplied yet
/// are shown disabled with "Not set up yet", never with invented content.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _notYet = 'Not set up yet';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.theme;
    final api = scope.api;
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
            const _SectionHeader('Feedback and contact'),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.feedback_outlined),
              title: Text('Send feedback'),
              subtitle: Text(_notYet),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.support_agent),
              title: Text('Contact support'),
              subtitle: Text(_notYet),
            ),
            const Divider(),
            const _SectionHeader('Support Pitchy'),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.volunteer_activism_outlined),
              title: Text('Support development'),
              subtitle: Text('Optional donations. $_notYet'),
            ),
            const Divider(),
            const _SectionHeader('Updates'),
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('Check for updates'),
              subtitle: Text('Pitchy ${scope.info.label}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showUpdateCheck(context),
            ),
            const Divider(),
            const _SectionHeader('About'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Pitchy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.about),
            ),
            ListTile(
              leading: const Icon(Icons.attribution_outlined),
              title: const Text('Credits'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.credits),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Privacy policy'),
              subtitle: Text(_notYet),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.health_and_safety_outlined),
              title: Text('Safety disclaimer'),
              subtitle: Text(_notYet),
            ),
            if (kDebugMode) ...[
              const Divider(),
              const _SectionHeader('Developer (debug builds only)'),
              if (api is MockPitchyApi) _MockScenarioPicker(api: api),
              ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('Component states'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.stateGallery),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Debug only: which state the mock backend is in. Pull to refresh the
/// dashboard afterwards.
class _MockScenarioPicker extends StatefulWidget {
  const _MockScenarioPicker({required this.api});

  final MockPitchyApi api;

  @override
  State<_MockScenarioPicker> createState() => _MockScenarioPickerState();
}

class _MockScenarioPickerState extends State<_MockScenarioPicker> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: DropdownMenu<MockScenario>(
      label: const Text('Mock backend scenario'),
      initialSelection: widget.api.scenario,
      onSelected: (s) => setState(() => widget.api.scenario = s ?? widget.api.scenario),
      dropdownMenuEntries: [
        for (final s in MockScenario.values) DropdownMenuEntry(value: s, label: s.name),
      ],
    ),
  );
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
