import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_telefon_helper.dart';

class V3ONamaScreen extends StatefulWidget {
  const V3ONamaScreen({super.key});

  @override
  State<V3ONamaScreen> createState() => _V3ONamaScreenState();
}

class _V3ONamaScreenState extends State<V3ONamaScreen> {
  String _appVersion = '';

  // Prevodi za O nama ekran (SR/EN/RU/DE) — isti obrazac kao welcome/profil ekran.
  static const Map<String, Map<String, String>> _t = {
    'title': {'sr': '📖 O nama', 'en': '📖 About us', 'ru': '📖 О нас', 'de': '📖 Über uns'},
    'limoServis': {'sr': 'Limo servis', 'en': 'Limo service', 'ru': 'Лимо-сервис', 'de': 'Limo-Service'},
    'iznajmljivanje': {
      'sr': 'Iznajmljivanje putničkih vozila sa vozačem',
      'en': 'Passenger vehicle rental with driver',
      'ru': 'Аренда легковых автомобилей с водителем',
      'de': 'Vermietung von Personenfahrzeugen mit Fahrer',
    },
    'od2003': {'sr': 'Od 2003. godine', 'en': 'Since 2003', 'ru': 'С 2003 года', 'de': 'Seit 2003'},
    'nasaPrica': {'sr': 'Naša priča', 'en': 'Our story', 'ru': 'Наша история', 'de': 'Unsere Geschichte'},
    'prica1': {
      'sr': 'Limo servis "Gavra 013" osnovan je 25. aprila 2003. godine u Beloj Crkvi.',
      'en': 'Limo service "Gavra 013" was founded on April 25, 2003 in Bela Crkva.',
      'ru': 'Лимо-сервис «Gavra 013» основан 25 апреля 2003 года в городе Бела Црква.',
      'de': 'Der Limo-Service "Gavra 013" wurde am 25. April 2003 in Bela Crkva gegründet.',
    },
    'prica2': {
      'sr':
          'Firmu je osnovao Branislav Gavrilović, a danas je vodi njegov sin Bojan Gavrilović, nastavljajući porodičnu tradiciju kvalitetnog prevoza putnika.',
      'en':
          'The company was founded by Branislav Gavrilović, and today it is run by his son Bojan Gavrilović, continuing the family tradition of quality passenger transport.',
      'ru':
          'Компанию основал Бранислав Гаврилович, а сегодня её возглавляет его сын Боян Гаврилович, продолжая семейную традицию качественных пассажирских перевозок.',
      'de':
          'Das Unternehmen wurde von Branislav Gavrilović gegründet und wird heute von seinem Sohn Bojan Gavrilović geführt, der die Familientradition des hochwertigen Personentransports fortsetzt.',
    },
    'prica3': {
      'sr': 'Više od 20 godina pružamo pouzdanu uslugu prevoza putnika.',
      'en': 'For over 20 years we have been providing reliable passenger transport service.',
      'ru': 'Более 20 лет мы предоставляем надёжные услуги пассажирских перевозок.',
      'de': 'Seit über 20 Jahren bieten wir zuverlässigen Personentransport an.',
    },
    'kontakt': {'sr': 'Kontakt', 'en': 'Contact', 'ru': 'Контакты', 'de': 'Kontakt'},
    'adresa': {'sr': 'Adresa', 'en': 'Address', 'ru': 'Адрес', 'de': 'Adresse'},
    'mobilni': {'sr': 'Mobilni', 'en': 'Mobile', 'ru': 'Мобильный', 'de': 'Mobil'},
    'podaciOFirmi': {
      'sr': 'Podaci o firmi',
      'en': 'Company information',
      'ru': 'Информация о компании',
      'de': 'Unternehmensangaben'
    },
    'punNaziv': {'sr': 'Pun naziv', 'en': 'Full name', 'ru': 'Полное название', 'de': 'Vollständiger Name'},
    'delatnost': {'sr': 'Delatnost', 'en': 'Activity', 'ru': 'Деятельность', 'de': 'Tätigkeit'},
    'delatnostVal': {
      'sr': '4932 - Limo servis + Taksi prevoz',
      'en': '4932 - Limo service + Taxi transport',
      'ru': '4932 - Лимо-сервис + Такси-перевозки',
      'de': '4932 - Limo-Service + Taxiverkehr',
    },
    'pib': {'sr': 'PIB', 'en': 'Tax ID', 'ru': 'ИНН', 'de': 'Steuernummer'},
    'maticniBroj': {
      'sr': 'Matični broj',
      'en': 'Registration number',
      'ru': 'Регистрационный номер',
      'de': 'Handelsregisternummer'
    },
    'datumOsnivanja': {'sr': 'Datum osnivanja', 'en': 'Founding date', 'ru': 'Дата основания', 'de': 'Gründungsdatum'},
    'ziroRacun': {'sr': 'Žiro račun', 'en': 'Bank account', 'ru': 'Расчётный счёт', 'de': 'Bankkonto'},
    'vlasnik': {'sr': 'Vlasnik', 'en': 'Owner', 'ru': 'Владелец', 'de': 'Inhaber'},
    'aplikacija': {'sr': 'Aplikacija', 'en': 'Application', 'ru': 'Приложение', 'de': 'Anwendung'},
    'verzija': {'sr': 'Verzija', 'en': 'Version', 'ru': 'Версия', 'de': 'Version'},
    'platforma': {'sr': 'Platforma', 'en': 'Platform', 'ru': 'Платформа', 'de': 'Plattform'},
    'copyright': {
      'sr': '© 2024-2026 Gavra 013. Sva prava zadržana.',
      'en': '© 2024-2026 Gavra 013. All rights reserved.',
      'ru': '© 2024-2026 Gavra 013. Все права защищены.',
      'de': '© 2024-2026 Gavra 013. Alle Rechte vorbehalten.',
    },
    'uSecanje': {
      'sr': 'U sećanje na Branislava Gavrilovića',
      'en': 'In memory of Branislav Gavrilović',
      'ru': 'Памяти Бранислава Гавриловича',
      'de': 'In Erinnerung an Branislav Gavrilović',
    },
    'osnivac': {
      'sr': 'Osnivač Gavra 013',
      'en': 'Founder of Gavra 013',
      'ru': 'Основатель Gavra 013',
      'de': 'Gründer von Gavra 013'
    },
  };

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      V3StateUtils.safeSetState(this, () => _appVersion = 'v${info.version} (${info.buildNumber})');
    } catch (_) {
      if (!mounted) return;
      V3StateUtils.safeSetState(this, () => _appVersion = 'v1.0.0');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    await V3TelefonHelper.pozovi(this, context, phoneNumber);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: V3LocaleManager().localeNotifier,
      builder: (context, _, __) => V3ContainerUtils.gradientContainer(
        gradient: V3ThemeManager().currentGradient,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(
              _tr('title'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeader(context, _tr),
                const SizedBox(height: 24),
                _buildGlassCard(
                  icon: Icons.history,
                  title: _tr('nasaPrica'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('prica1'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _tr('prica2'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _tr('prica3'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlassCard(
                  icon: Icons.contact_phone,
                  title: _tr('kontakt'),
                  child: Column(
                    children: [
                      _buildContactRow(
                        icon: Icons.location_on,
                        label: _tr('adresa'),
                        value: 'Mihajla Pupina 74, 26340 Bela Crkva',
                      ),
                      const Divider(color: Colors.white24, height: 20),
                      _buildContactRow(
                        icon: Icons.phone_android,
                        label: _tr('mobilni'),
                        value: '064/116-2560',
                        onTap: () => _makePhoneCall('0641162560'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlassCard(
                  icon: Icons.business,
                  title: _tr('podaciOFirmi'),
                  child: Column(
                    children: [
                      _buildInfoRow(_tr('punNaziv'), 'PR LIMO SERVIS GAVRA 013'),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('delatnost'), _tr('delatnostVal')),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('pib'), '102853497'),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('maticniBroj'), '55572178'),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('datumOsnivanja'), '25.04.2003.'),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('ziroRacun'), '340-11436537-92'),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('vlasnik'), 'Bojan Gavrilović'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlassCard(
                  icon: Icons.phone_android,
                  title: _tr('aplikacija'),
                  child: Column(
                    children: [
                      _buildInfoRow(_tr('verzija'), _appVersion),
                      const Divider(color: Colors.white24, height: 16),
                      _buildInfoRow(_tr('platforma'), 'Android'),
                      const SizedBox(height: 12),
                      Text(
                        _tr('copyright'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                V3ContainerUtils.iconContainer(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  borderRadiusGeometry: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  child: Column(
                    children: [
                      const Text('🕯️', style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 8),
                      Text(
                        _tr('uSecanje'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _tr('osnivac'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildHeader(BuildContext context, String Function(String) tr) {
    return Column(
      children: [
        V3ContainerUtils.iconContainer(
          width: V3ContainerUtils.responsiveHeight(context, 120),
          height: V3ContainerUtils.responsiveHeight(context, 120),
          backgroundColor: Colors.black,
          borderRadiusGeometry: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset(
              'assets/logo_transparent.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Gavra 013',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            shadows: [Shadow(offset: Offset(0, 2), blurRadius: 4, color: Colors.black38)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr('limoServis'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          tr('iznajmljivanje'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        V3ContainerUtils.iconContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          backgroundColor: Colors.green.withValues(alpha: 0.3),
          borderRadiusGeometry: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                tr('od2003'),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildGlassCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return V3ContainerUtils.gradientContainer(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.05),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  static Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: Colors.white60, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.4), size: 16),
          ],
        ),
      ),
    );
  }

  static Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
