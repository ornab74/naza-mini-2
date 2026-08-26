import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/glass.dart';
import 'safety_tips.dart';

class NazaShell extends StatefulWidget {
  const NazaShell({super.key, required this.controller});
  final NazaController controller;

  @override
  State<NazaShell> createState() => _NazaShellState();
}

class _NazaShellState extends State<NazaShell> {
  NazaController get controller => widget.controller;

  static const _menuSections = <NazaSection>[
    NazaSection.roadScanner,
    NazaSection.scanHistory,
    NazaSection.settings,
  ];

  static const _icons = <NazaSection, IconData>{
    NazaSection.mainMenu: Icons.grid_view_rounded,
    NazaSection.modelManager: Icons.memory_rounded,
    NazaSection.settings: Icons.tune_rounded,
    NazaSection.roadScanner: Icons.route_rounded,
    NazaSection.defenseLab: Icons.shield_moon_rounded,
    NazaSection.scanHistory: Icons.history_rounded,
    NazaSection.rekey: Icons.key_rounded,
    NazaSection.exit: Icons.logout_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.9),
          radius: 1.45,
          colors: [Color(0xFF33235F), Color(0xFF15162A), Color(0xFF090A12)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 980;
                  return Column(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _TopBar(controller: controller),
                            if (controller.busy)
                              LinearProgressIndicator(
                                value: controller.progress
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                                minHeight: 2,
                              ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  desktop ? 28 : 10,
                                  desktop ? 14 : 8,
                                  desktop ? 28 : 10,
                                  desktop ? 18 : 10,
                                ),
                                child: _ScreenRouter(
                                  controller: controller,
                                  menuSections: _menuSections,
                                  icons: _icons,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _BottomNavigation(
                        controller: controller,
                        sections: _menuSections,
                        icons: _icons,
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// The app now uses the three-item bottom navigation on every screen. Keep the
// old widget source out of the active tree while older hot-restart state dies.
// ignore: unused_element
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.icons,
    required this.sections,
  });
  final NazaController controller;
  final Map<NazaSection, IconData> icons;
  final List<NazaSection> sections;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 284,
      margin: const EdgeInsets.all(16),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => unawaited(controller.navigate(NazaSection.mainMenu)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF795CFF),
                            Color(0xFF41D8FF),
                            Color(0xFFE056B4),
                          ],
                        ),
                      ),
                      child: const Icon(Icons.hub_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NAZA',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'LlamaDart Road Scanner',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  final active = controller.section == section;
                  return Material(
                    color: active
                        ? Colors.white.withValues(alpha: 0.09)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => section == NazaSection.exit
                          ? unawaited(controller.exitApp())
                          : unawaited(controller.navigate(section)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            GradientIcon(icons[section]!, size: 20),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                section.label,
                                style: TextStyle(
                                  color: active ? Colors.white : Colors.white70,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (active)
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Colors.white60,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            StatusPill(
              label: controller.status,
              icon: controller.busy ? Icons.sync_rounded : Icons.lock_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});
  final NazaController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 18,
            10,
            compact ? 8 : 18,
            2,
          ),
          child: Row(
            children: [
              const GradientIcon(Icons.route_rounded, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  controller.section == NazaSection.mainMenu
                      ? 'NAZA Road Scanner'
                      : controller.section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!compact)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: StatusPill(
                    label: controller.busy ? 'Working…' : controller.status,
                    icon: controller.busy
                        ? Icons.sync_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
                ),
              IconButton(
                tooltip: 'Scan',
                onPressed: () =>
                    unawaited(controller.navigate(NazaSection.roadScanner)),
                icon: const Icon(Icons.radar_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.controller,
    required this.sections,
    required this.icons,
  });

  final NazaController controller;
  final List<NazaSection> sections;
  final Map<NazaSection, IconData> icons;

  @override
  Widget build(BuildContext context) {
    final selected = sections.indexOf(controller.section);
    return NavigationBar(
      height: 72,
      backgroundColor: Colors.black.withValues(alpha: 0.28),
      indicatorColor: const Color(0xFF7C5CFF).withValues(alpha: 0.28),
      selectedIndex: selected < 0
          ? sections.indexOf(NazaSection.settings)
          : selected,
      onDestinationSelected: (index) {
        if (!controller.busy) unawaited(controller.navigate(sections[index]));
      },
      destinations: [
        for (final section in sections)
          NavigationDestination(
            icon: Icon(icons[section]),
            selectedIcon: Icon(icons[section]),
            label: switch (section) {
              NazaSection.roadScanner => 'Scan',
              NazaSection.scanHistory => 'History',
              NazaSection.settings => 'Settings',
              _ => section.label,
            },
          ),
      ],
    );
  }
}

class _ScreenRouter extends StatelessWidget {
  const _ScreenRouter({
    required this.controller,
    required this.menuSections,
    required this.icons,
  });
  final NazaController controller;
  final List<NazaSection> menuSections;
  final Map<NazaSection, IconData> icons;

  @override
  Widget build(BuildContext context) {
    return switch (controller.section) {
      NazaSection.mainMenu => _MainMenuPage(
        controller: controller,
        menuSections: menuSections,
        icons: icons,
      ),
      NazaSection.modelManager => _ModelManagerPage(controller: controller),
      NazaSection.settings => _SettingsPage(controller: controller),
      NazaSection.roadScanner => _RoadScannerPage(controller: controller),
      NazaSection.defenseLab => _DefenseLabPage(controller: controller),
      NazaSection.scanHistory => _ScanHistoryPage(controller: controller),
      NazaSection.rekey => _RekeyPage(controller: controller),
      NazaSection.exit => _MainMenuPage(
        controller: controller,
        menuSections: menuSections,
        icons: icons,
      ),
    };
  }
}

class _MainMenuPage extends StatelessWidget {
  const _MainMenuPage({
    required this.controller,
    required this.menuSections,
    required this.icons,
  });
  final NazaController controller;
  final List<NazaSection> menuSections;
  final Map<NazaSection, IconData> icons;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Main Menu',
          subtitle: 'Choose a mode and keep moving.',
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 330,
              mainAxisExtent: 150,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: menuSections.length,
            itemBuilder: (context, index) {
              final section = menuSections[index];
              return _MenuCard(
                label: section.label,
                icon: icons[section]!,
                onTap: () => section == NazaSection.exit
                    ? unawaited(controller.exitApp())
                    : unawaited(controller.navigate(section)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GradientIcon(icon, size: 30),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white54,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelManagerPage extends StatelessWidget {
  const _ModelManagerPage({required this.controller});
  final NazaController controller;

  static const actions = <String>[
    'Download or repair the model',
    'Change model mirror (advanced)',
    'Check the model file',
    'Protect the model',
    'Temporarily open the protected model',
    'Delete the unprotected copy',
    'Back to Settings',
  ];

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Model & secure storage',
          subtitle: 'Repair the model or check its protected copy when needed.',
        ),
        SizedBox(height: compact ? 10 : 16),
        GlassPanel(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(label: 'Model: ${controller.selectedModel.name}'),
                  const StatusPill(label: 'GitHub: active'),
                  const StatusPill(label: 'Hugging Face: active'),
                  StatusPill(
                    label: controller.pinataModelUrl.isEmpty
                        ? 'Pinata: add mirror'
                        : 'Pinata: active',
                  ),
                  const StatusPill(label: 'SHA-256 pinned'),
                  StatusPill(
                    label: 'Fast crypto: ${controller.crypto.backendLabel}',
                  ),
                ],
              ),
              if (controller.busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: controller.progress.clamp(0.0, 1.0).toDouble(),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.status,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => GlassPanel(
              padding: EdgeInsets.zero,
              radius: compact ? 16 : 18,
              child: ListTile(
                dense: compact,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 16,
                  vertical: compact ? 2 : 5,
                ),
                leading: GradientIcon(_modelActionIcon(index)),
                title: Text(actions[index]),
                subtitle: index == 1 && controller.pinataModelUrl.isNotEmpty
                    ? Text(
                        controller.pinataModelUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white38,
                ),
                enabled: !controller.busy,
                onTap: () => _handle(context, index),
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _modelActionIcon(int index) => const [
    Icons.downloading_rounded,
    Icons.hub_rounded,
    Icons.verified_rounded,
    Icons.lock_rounded,
    Icons.lock_open_rounded,
    Icons.delete_outline_rounded,
    Icons.arrow_back_rounded,
  ][index];

  Future<void> _handle(BuildContext context, int index) async {
    try {
      switch (index) {
        case 0:
          await controller.downloadActiveModel();
          break;
        case 1:
          await _configurePinataMirror(context);
          break;
        case 2:
          final result = await controller.verifyActiveModel();
          if (context.mounted) {
            await _message(context, 'SHA256 verification', result);
          }
          break;
        case 3:
          await controller.encryptActiveModel();
          break;
        case 4:
          await controller.decryptActiveModel();
          break;
        case 5:
          if (await _confirm(
            context,
            'Delete plaintext model?',
            'The encrypted .aes copy will be kept.',
          )) {
            await controller.deleteActivePlaintext();
          }
          break;
        case 6:
          await controller.navigate(NazaSection.settings);
          break;
      }
    } catch (e) {
      if (context.mounted) await _message(context, 'Model Manager', '$e');
    }
  }

  Future<void> _configurePinataMirror(BuildContext context) async {
    final field = TextEditingController(text: controller.pinataModelUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pinata / IPFS model mirror'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: field,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText:
                  'https://your-gateway.mypinata.cloud/ipfs/CID\nor ipfs://CID',
              helperText:
                  'HTTPS Pinata gateways only. Leave blank to reset the built-in third mirror.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('Save mirror'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    await controller.setPinataModelUrl(value);
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller});
  final NazaController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Settings',
            subtitle:
                'Simple controls for scanning, privacy, the model, and security.',
          ),
          const SizedBox(height: 8),
          const TabBar(
            tabs: [
              Tab(text: 'Settings'),
              Tab(text: 'Safety Tips'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [_settingsList(context), const SafetyTipsPage()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsList(BuildContext context) {
    final s = controller.settings;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _settingGroup(
          context,
          'Scan style',
          DropdownButtonFormField<String>(
            value: s.defenseProfile,
            items: SecuritySettings.presets.keys
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(name[0].toUpperCase() + name.substring(1)),
                  ),
                )
                .toList(),
            onChanged: (name) {
              if (name != null)
                unawaited(controller.updateSettings(s.applyPreset(name)));
            },
          ),
        ),
        _switchSetting(
          'Use several safety checks',
          s.defenseVoting,
          (v) => controller.updateSettings(s.copyWith(defenseVoting: v)),
          subtitle: 'More checks can improve consistency but take longer.',
        ),
        _switchSetting(
          'Use extra device checks',
          s.colorwheelEnabled,
          (v) => controller.updateSettings(s.copyWith(colorwheelEnabled: v)),
          subtitle: 'Adds local checks when you need a more careful scan.',
        ),
        _switchSetting(
          'Save scans to History',
          s.saveScanHistory,
          (v) => controller.updateSettings(s.copyWith(saveScanHistory: v)),
          subtitle:
              'Off by default. Turn this on when you want automatic encrypted history.',
        ),
        _switchSetting(
          'Extra model trace protection',
          s.mlTraceScramble,
          (v) => controller.updateSettings(s.copyWith(mlTraceScramble: v)),
        ),
        _sliderSetting(
          'Extra checks',
          s.colorwheelSpins.toDouble(),
          16,
          256,
          240,
          (v) =>
              controller.updateSettings(s.copyWith(colorwheelSpins: v.round())),
        ),
        _sliderSetting(
          'Check rounds',
          s.colorwheelRings.toDouble(),
          6,
          24,
          18,
          (v) =>
              controller.updateSettings(s.copyWith(colorwheelRings: v.round())),
        ),
        _sliderSetting(
          'Maximum safety passes',
          s.maxDefensePasses.toDouble(),
          1,
          5,
          4,
          (v) => controller.updateSettings(
            s.copyWith(maxDefensePasses: v.round()),
          ),
        ),
        _sliderSetting(
          'Local samples',
          s.metricSamples.toDouble(),
          3,
          13,
          10,
          (v) =>
              controller.updateSettings(s.copyWith(metricSamples: v.round())),
        ),
        _sliderSetting(
          'Noise protection',
          s.noiseWidth.toDouble(),
          1,
          4,
          3,
          (v) => controller.updateSettings(s.copyWith(noiseWidth: v.round())),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 10, 4, 8),
          child: Text(
            'Model and security',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        _actionSetting(
          'Model setup and repair',
          Icons.memory_rounded,
          () => controller.navigate(NazaSection.modelManager),
        ),
        _actionSetting(
          'Change encryption key',
          Icons.key_rounded,
          () => controller.navigate(NazaSection.rekey),
        ),
        _actionSetting(
          'Advanced checks',
          Icons.shield_rounded,
          () => controller.navigate(NazaSection.defenseLab),
        ),
        _actionSetting(
          'Run a quick device check',
          Icons.color_lens_rounded,
          () async {
            final marker = controller.runColorwheelTest();
            await _message(context, 'Device check', marker);
          },
        ),
        _actionSetting(
          'Restore standard settings',
          Icons.restart_alt_rounded,
          () async {
            if (await _confirm(
              context,
              'Restore standard settings?',
              'Your scan style will return to the simple defaults.',
            )) {
              await controller.resetSettings();
            }
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _settingGroup(BuildContext context, String label, Widget child) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassPanel(
          radius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget _switchSetting(
    String label,
    bool value,
    Future<void> Function(bool) onChanged, {
    String? subtitle,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: (v) => unawaited(onChanged(v)),
      ),
    ),
  );

  Widget _sliderSetting(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    Future<void> Function(double) onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassPanel(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                value.round().toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => unawaited(onChanged(v)),
          ),
        ],
      ),
    ),
  );

  Widget _actionSetting(
    String label,
    IconData icon,
    Future<void> Function() onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassPanel(
      padding: EdgeInsets.zero,
      radius: 18,
      child: ListTile(
        leading: GradientIcon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => unawaited(onTap()),
      ),
    ),
  );
}

class _RoadScannerPage extends StatefulWidget {
  const _RoadScannerPage({required this.controller});
  final NazaController controller;

  @override
  State<_RoadScannerPage> createState() => _RoadScannerPageState();
}

class _RoadScannerPageState extends State<_RoadScannerPage> {
  final location = TextEditingController();
  int mode = 1;

  @override
  void dispose() {
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.controller.roadResult;
    if (!widget.controller.bootComplete) return _bootView(context);
    if (result != null) return _resultView(context, result);
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Road Scanner',
          subtitle: 'Capture a road location and classify risk.',
        ),
        SizedBox(height: compact ? 10 : 16),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              GlassPanel(
                padding: EdgeInsets.all(compact ? 14 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const GradientIcon(Icons.route_rounded, size: 24),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Road classification generation',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        StatusPill(
                          label: mode == 1
                              ? 'CHUNKD'
                              : mode == 2
                              ? 'CHUNKD'
                              : 'Direct',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: location,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _runScan(),
                      decoration: const InputDecoration(
                        labelText: 'Where are you going?',
                        hintText:
                            'Enter the road or destination you are traveling to',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    RadioListTile<int>(
                      dense: compact,
                      contentPadding: EdgeInsets.zero,
                      value: 1,
                      groupValue: mode,
                      title: const Text('1) CHUNKD generation (recommended)'),
                      onChanged: widget.controller.busy
                          ? null
                          : (v) => setState(() => mode = v!),
                    ),
                    RadioListTile<int>(
                      dense: compact,
                      contentPadding: EdgeInsets.zero,
                      value: 2,
                      groupValue: mode,
                      title: const Text('2) Chunked only'),
                      onChanged: widget.controller.busy
                          ? null
                          : (v) => setState(() => mode = v!),
                    ),
                    RadioListTile<int>(
                      dense: compact,
                      contentPadding: EdgeInsets.zero,
                      value: 3,
                      groupValue: mode,
                      title: const Text('3) Direct single-call generation'),
                      onChanged: widget.controller.busy
                          ? null
                          : (v) => setState(() => mode = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (widget.controller.busy)
                GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        value: widget.controller.progress
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        widget.controller.status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _runScan,
                  icon: const Icon(Icons.radar_rounded),
                  label: Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
                    child: Text(
                      mode == 1
                          ? 'Scan with CHUNKD'
                          : mode == 2
                          ? 'Scan with CHUNKD'
                          : 'Scan direct',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bootView(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Starting Road Scanner',
          subtitle:
              'One-time secure model setup, then automatic scanner startup.',
        ),
        SizedBox(height: compact ? 10 : 16),
        Expanded(
          child: ListView(
            children: [
              GlassPanel(
                padding: EdgeInsets.all(compact ? 16 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const GradientIcon(
                          Icons.rocket_launch_rounded,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            controller.firstBootSetup
                                ? 'First boot setup'
                                : 'Loading secure model',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      controller.firstBootSetup
                          ? 'NAZA is downloading the verified Llama 3 Small model, encrypting it, and removing the plaintext copy. This happens once on this device.'
                          : 'NAZA is decrypting the protected model into a temporary runtime file and loading the Road Scanner.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'How to use it',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'After startup, enter the road or destination you are traveling to, choose CHUNKD, and tap Scan. Confirm the result against current on-site conditions; it is decision support, not a replacement for direct inspection.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB74D).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(
                            0xFFFFB74D,
                          ).withValues(alpha: 0.42),
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warning',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFD180),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Accuracy depends on the real-world conditions around you. A Low result must never encourage irrational or risk-taking behavior. The model cannot always forecast the complete risk of a trip. Seat belts, not speeding, turn signals, essential road rules, active peripheral vision, proper stops, waiting, and not rushing are always required for safe driving and matter more than any forecast.',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.busy) ...[
                      const SizedBox(height: 18),
                      LinearProgressIndicator(
                        value: controller.progress.clamp(0.0, 1.0).toDouble(),
                        minHeight: 7,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        controller.status,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    if (controller.bootError != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        controller.bootError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => unawaited(controller.bootstrap()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry startup'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _runScan() async {
    if (widget.controller.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await widget.controller.runRoadScan(location.text, mode);
    } catch (error) {
      if (!mounted) return;
      await _message(context, 'Road Scanner', error.toString());
    }
  }

  Widget _resultView(BuildContext context, RoadScanResult result) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final detailStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.82),
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Road Scanner Result',
          subtitle:
              'Review the result, compare it with the road, then choose what to do next.',
        ),
        SizedBox(height: compact ? 10 : 14),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              GlassPanel(
                padding: EdgeInsets.all(compact ? 14 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            result.classification,
                            style: TextStyle(
                              fontSize: compact ? 38 : 46,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: _riskColor(result.classification),
                            ),
                          ),
                        ),
                        StatusPill(label: result.generator),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusPill(label: 'Votes: ${result.votes.join(', ')}'),
                        StatusPill(label: 'Model: ${result.model}'),
                        StatusPill(label: result.multiNode),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ResultDetail(
                      label: 'Colorwheel',
                      value: result.colorwheel,
                      style: detailStyle,
                    ),
                    const SizedBox(height: 9),
                    _ResultDetail(
                      label: 'Defense',
                      value: result.defenseCapsule,
                      style: detailStyle,
                    ),
                    const SizedBox(height: 9),
                    _ResultDetail(
                      label: 'Model output',
                      value: result.generatedOutput,
                      style: detailStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                padding: EdgeInsets.all(compact ? 12 : 18),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _resultActions(context),
                      )
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: _resultActions(context),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _resultActions(BuildContext context) => [
    OutlinedButton.icon(
      onPressed: widget.controller.busy
          ? null
          : () => widget.controller.startNewRoadScan(),
      icon: const Icon(Icons.edit_rounded),
      label: const Text('Scan again'),
    ),
    OutlinedButton.icon(
      onPressed: () async {
        try {
          final path = await widget.controller.exportRoadScan();
          if (context.mounted) {
            await _message(context, 'Export to JSON', path);
          }
        } catch (e) {
          if (context.mounted) {
            await _message(context, 'Export to JSON', '$e');
          }
        }
      },
      icon: const Icon(Icons.save_alt_rounded),
      label: const Text('Export JSON'),
    ),
    if (!widget.controller.roadResultSaved)
      OutlinedButton.icon(
        onPressed: widget.controller.busy
            ? null
            : () async {
                try {
                  await widget.controller.saveRoadScanToHistory();
                } catch (e) {
                  if (context.mounted)
                    await _message(context, 'Save to History', '$e');
                }
              },
        icon: const Icon(Icons.history_rounded),
        label: const Text('Save to History'),
      )
    else
      const Chip(
        avatar: Icon(Icons.check_rounded, size: 17),
        label: Text('Saved to History'),
      ),
    FilledButton.icon(
      onPressed: widget.controller.busy
          ? null
          : () => widget.controller.startNewRoadScan(),
      icon: const Icon(Icons.arrow_forward_rounded),
      label: const Text('Next: scan another trip'),
    ),
    TextButton(
      onPressed: () =>
          unawaited(widget.controller.navigate(NazaSection.scanHistory)),
      child: const Text('Open History'),
    ),
  ];

  Color _riskColor(String label) => switch (label) {
    'High' => const Color(0xFFFF6B7A),
    'Low' => const Color(0xFF68E0B2),
    _ => const Color(0xFFFFC863),
  };
}

class _ResultDetail extends StatelessWidget {
  const _ResultDetail({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white54,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        SelectableText(value, style: style),
      ],
    );
  }
}

class _DefenseLabPage extends StatelessWidget {
  const _DefenseLabPage({required this.controller});
  final NazaController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot =
        controller.defenseSnapshot ?? controller.refreshDefenseLab();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(
                title: 'Advanced checks',
                subtitle:
                    'Optional device checks for troubleshooting and extra review.',
              ),
            ),
            IconButton(
              onPressed: controller.refreshDefenseLab,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              GlassPanel(
                child: SelectableText(
                  '${snapshot.capsule}\n${snapshot.colorwheel}\nlocal_interference=${snapshot.interference.toStringAsFixed(2)}\nmulti_node=${snapshot.multiNode.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Check details',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final entry in snapshot.vectorScores.entries) ...[
                      Row(
                        children: [
                          Expanded(child: Text(entry.key)),
                          Text(entry.value.toStringAsFixed(2)),
                        ],
                      ),
                      LinearProgressIndicator(
                        value: entry.value,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommendations',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final rec in snapshot.recommendations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• $rec'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanHistoryPage extends StatefulWidget {
  const _ScanHistoryPage({required this.controller});
  final NazaController controller;

  @override
  State<_ScanHistoryPage> createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<_ScanHistoryPage> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'History',
          subtitle: 'Saved scans stay encrypted on this device.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                decoration: const InputDecoration(
                  hintText: 'Search saved scans',
                ),
                onSubmitted: (value) =>
                    unawaited(c.setScanHistorySearch(value)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => unawaited(c.setScanHistorySearch(search.text)),
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: c.scanHistory.isEmpty
              ? const Center(
                  child: Text(
                    'No saved scans yet. Turn on “Save scans to History” in Settings or save a result manually.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  itemCount: c.scanHistory.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final row = c.scanHistory[index];
                    return GlassPanel(
                      radius: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[${row.id}] ${row.timestamp}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            'Location: ${row.location}\nClassification: ${row.classification}\nModel: ${row.model}\nGenerator: ${row.generator}',
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 10),
        GlassPanel(
          padding: const EdgeInsets.all(10),
          radius: 18,
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: c.scanHistoryPage > 0
                    ? () => unawaited(c.scanHistoryPrevious())
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('Page ${c.scanHistoryPage + 1}'),
              IconButton(
                tooltip: 'Next page',
                onPressed:
                    c.scanHistory.length == NazaController.scanHistoryPageSize
                    ? () => unawaited(c.scanHistoryNext())
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              TextButton(
                onPressed: () => unawaited(c.navigate(NazaSection.roadScanner)),
                child: const Text('Back to Scan'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RekeyPage extends StatelessWidget {
  const _RekeyPage({required this.controller});
  final NazaController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Change security key',
          subtitle:
              'Create a new key and re-protect the stored model and History.',
        ),
        const SizedBox(height: 18),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose how to protect your stored data.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () async {
                        try {
                          await controller.rekeyRandom();
                          if (context.mounted)
                            await _message(
                              context,
                              'Security key changed',
                              'A new random key was created and stored data was re-protected.',
                            );
                        } catch (e) {
                          if (context.mounted)
                            await _message(
                              context,
                              'Security key change',
                              '$e',
                            );
                        }
                      },
                icon: const Icon(Icons.casino_rounded),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Create a new random key'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: controller.busy
                    ? null
                    : () => _passphraseFlow(context),
                icon: const Icon(Icons.password_rounded),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Use a passphrase'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () =>
                    unawaited(controller.navigate(NazaSection.settings)),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _passphraseFlow(BuildContext context) async {
    final one = TextEditingController();
    final two = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Passphrase-derived key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: one,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter new passphrase',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: two,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (one.text != two.text) return;
              Navigator.pop(context, one.text);
            },
            child: const Text('Change key'),
          ),
        ],
      ),
    );
    one.dispose();
    two.dispose();
    if (value == null) return;
    try {
      await controller.rekeyPassphrase(value);
      if (context.mounted)
        await _message(
          context,
          'Security key changed',
          'Your passphrase-based key was saved and stored data was re-protected.',
        );
    } catch (e) {
      if (context.mounted) await _message(context, 'Security key change', '$e');
    }
  }
}

Future<void> _message(BuildContext context, String title, String body) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;
