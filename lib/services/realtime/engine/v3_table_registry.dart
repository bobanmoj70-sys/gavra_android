enum V3RealtimeHook {
  rebuildGpsCache,
  applyGlobalAppSettings,
}

class V3RealtimeTableConfig {
  const V3RealtimeTableConfig({
    required this.name,
    this.activeKey = 'is_active',
    this.hasActiveKey = false,
    this.keepInactive = false,
    this.dependsOn = const <String>[],
    this.hooks = const <V3RealtimeHook>[],
  });

  final String name;
  final String activeKey;
  final bool hasActiveKey;
  final bool keepInactive;
  final List<String> dependsOn;
  final List<V3RealtimeHook> hooks;
}

class V3RealtimeTableRegistry {
  static const List<V3RealtimeTableConfig> defaults = <V3RealtimeTableConfig>[
    V3RealtimeTableConfig(name: 'v3_adrese', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_vozaci', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_putnici', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_vozila', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_zahtevi', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_gorivo', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_gorivo_promene', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_vozac_lokacije', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_finansije', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_racuni', hasActiveKey: false),
    V3RealtimeTableConfig(name: 'v3_racuni_arhiva', hasActiveKey: false),
    V3RealtimeTableConfig(
      name: 'v3_operativna_nedelja',
      hasActiveKey: false,
      keepInactive: true,
      hooks: <V3RealtimeHook>[V3RealtimeHook.rebuildGpsCache],
    ),
    V3RealtimeTableConfig(name: 'v3_kapacitet_slots', hasActiveKey: false),
    V3RealtimeTableConfig(
      name: 'v3_app_settings',
      hasActiveKey: false,
      hooks: <V3RealtimeHook>[V3RealtimeHook.applyGlobalAppSettings],
    ),
  ];

  static final Map<String, V3RealtimeTableConfig> byName = <String, V3RealtimeTableConfig>{
    for (final table in defaults) table.name: table,
  };
}
