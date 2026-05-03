enum V3RealtimeHook {
  rebuildAssignedCache,
  applyGlobalAppSettings,
}

class V3RealtimeTableConfig {
  const V3RealtimeTableConfig({
    required this.name,
    this.dependsOn = const <String>[],
    this.hooks = const <V3RealtimeHook>[],
  });

  final String name;
  final List<String> dependsOn;
  final List<V3RealtimeHook> hooks;
}

class V3RealtimeTableRegistry {
  static const List<V3RealtimeTableConfig> defaults = <V3RealtimeTableConfig>[
    V3RealtimeTableConfig(name: 'v3_adrese'),
    V3RealtimeTableConfig(name: 'v3_auth'),
    V3RealtimeTableConfig(name: 'v3_vozila'),
    V3RealtimeTableConfig(name: 'v3_zahtevi'),
    V3RealtimeTableConfig(name: 'v3_gorivo'),
    V3RealtimeTableConfig(name: 'v3_finansije'),
    V3RealtimeTableConfig(name: 'v3_racuni'),
    V3RealtimeTableConfig(name: 'v3_trenutna_dodela'),
    V3RealtimeTableConfig(name: 'v3_trenutna_dodela_slot'),
    V3RealtimeTableConfig(
      name: 'v3_operativna_nedelja',
      hooks: <V3RealtimeHook>[V3RealtimeHook.rebuildAssignedCache],
    ),
    V3RealtimeTableConfig(name: 'v3_kapacitet_slots'),
    V3RealtimeTableConfig(
      name: 'v3_app_settings',
      hooks: <V3RealtimeHook>[V3RealtimeHook.applyGlobalAppSettings],
    ),
  ];

  static final Map<String, V3RealtimeTableConfig> byName = <String, V3RealtimeTableConfig>{
    for (final table in defaults) table.name: table,
  };
}
