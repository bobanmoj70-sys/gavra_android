import 'package:flutter/material.dart';

import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

class V3HelpScreen extends StatelessWidget {
  const V3HelpScreen({super.key});

  static String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  // Naslovi sekcija i sadržaj su prevedeni za SR/EN/RU/DE.
  static const Map<String, Map<String, String>> _t = {
    'appBarTitle': {
      'sr': '❓ Uputstvo za korišćenje',
      'en': '❓ User guide',
      'ru': '❓ Инструкция по использованию',
      'de': '❓ Bedienungsanleitung',
    },
    'secBezbednost': {
      'sr': 'Bezbednost i sertifikati',
      'en': 'Security and certifications',
      'ru': 'Безопасность и сертификаты',
      'de': 'Sicherheit und Zertifizierungen',
    },
    'secPrijava': {'sr': 'Prijava (Log in)', 'en': 'Login', 'ru': 'Вход', 'de': 'Anmeldung'},
    'secZakazivanje': {
      'sr': 'Zakazivanje prevoza',
      'en': 'Scheduling a ride',
      'ru': 'Планирование поездки',
      'de': 'Fahrt planen',
    },
    'secObavestenja': {
      'sr': 'Obaveštenja (Push notifikacije)',
      'en': 'Notifications (Push)',
      'ru': 'Уведомления (Push)',
      'de': 'Benachrichtigungen (Push)',
    },
    'secBiometrija': {
      'sr': 'Biometrijska prijava',
      'en': 'Biometric login',
      'ru': 'Биометрический вход',
      'de': 'Biometrische Anmeldung',
    },
    'secAdrese': {'sr': 'Adrese', 'en': 'Addresses', 'ru': 'Адреса', 'de': 'Adressen'},
    'secAlternativa': {
      'sr': 'Alternativni termin',
      'en': 'Alternative time slot',
      'ru': 'Альтернативное время',
      'de': 'Alternativer Termin',
    },
    'secNeradniDani': {
      'sr': 'Neradni dani',
      'en': 'Non-working days',
      'ru': 'Нерабочие дни',
      'de': 'Arbeitsfreie Tage',
    },
    'secTipoviPutnika': {
      'sr': 'Tipovi putnika',
      'en': 'Passenger types',
      'ru': 'Типы пассажиров',
      'de': 'Fahrgastarten',
    },
  };

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.gradientContainer(
      gradient: V3ThemeManager().currentGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            _tr('appBarTitle'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _HelpSection(
              icon: Icons.verified_user,
              title: _tr('secBezbednost'),
              content: _content(
                sr: const [
                  'U skladu sa važećim propisima o zaštiti podataka, dužni smo da korisnike jasno obavestimo kako se njihovi podaci prikupljaju, čuvaju, obrađuju i koriste.',
                  '',
                  'Naša aplikacija izgrađena je na Google Firebase platformi, koja poseduje sledeće međunarodne sertifikate i standarde:',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🤖 ANDROID — Google Firebase',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – upravljanje bezbednošću informacija',
                  '🏅 ISO 27017 – bezbednost u cloud servisima',
                  '🏅 ISO 27018 – zaštita ličnih podataka u oblaku',
                  '🏅 SOC 1 / SOC 2 / SOC 3 – kontrola bezbednosti i dostupnosti',
                  '',
                  'Svi podaci se prenose putem TLS enkripcije.',
                  'Aplikacija je digitalno potpisana i distribuirana isključivo kroz Google Play Store.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🍎 iOS — Apple App Store',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – Apple infrastruktura',
                  '🏅 SOC 2 Type II – Apple data centri',
                  '',
                  'Svaka verzija aplikacije prolazi Apple-ovu zvaničnu bezbednosnu i kvalitetnu proveru pre objave na App Store-u.',
                  'Aplikacija je digitalno potpisana i distribuirana isključivo kroz Apple App Store.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🔐 Dodatna zaštita',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '• Biometrijski podaci čuvaju se isključivo u Android Keystore / Apple Secure Enclave – nikada na serveru',
                  '• Maksimalno 2 uređaja po nalogu – svaki neovlašćeni pristup se automatski blokira',
                  '• Push tokeni se kriptovano sinhronizuju pri svakoj prijavi',
                ],
                en: const [
                  'In accordance with applicable data protection regulations, we are required to clearly inform users how their data is collected, stored, processed and used.',
                  '',
                  'Our application is built on the Google Firebase platform, which holds the following international certifications and standards:',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🤖 ANDROID — Google Firebase',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – information security management',
                  '🏅 ISO 27017 – cloud service security',
                  '🏅 ISO 27018 – protection of personal data in the cloud',
                  '🏅 SOC 1 / SOC 2 / SOC 3 – security and availability controls',
                  '',
                  'All data is transmitted using TLS encryption.',
                  'The application is digitally signed and distributed exclusively through the Google Play Store.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🍎 iOS — Apple App Store',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – Apple infrastructure',
                  '🏅 SOC 2 Type II – Apple data centers',
                  '',
                  'Every version of the app goes through Apple\'s official security and quality review before being published on the App Store.',
                  'The application is digitally signed and distributed exclusively through the Apple App Store.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🔐 Additional protection',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '• Biometric data is stored exclusively in the Android Keystore / Apple Secure Enclave – never on a server',
                  '• Maximum of 2 devices per account – any unauthorized access is automatically blocked',
                  '• Push tokens are synchronized using encryption on every login',
                ],
                ru: const [
                  'В соответствии с действующими правилами защиты данных, мы обязаны четко информировать пользователей о том, как собираются, хранятся, обрабатываются и используются их данные.',
                  '',
                  'Наше приложение построено на платформе Google Firebase, которая имеет следующие международные сертификаты и стандарты:',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🤖 ANDROID — Google Firebase',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – управление информационной безопасностью',
                  '🏅 ISO 27017 – безопасность облачных сервисов',
                  '🏅 ISO 27018 – защита персональных данных в облаке',
                  '🏅 SOC 1 / SOC 2 / SOC 3 – контроль безопасности и доступности',
                  '',
                  'Все данные передаются с использованием шифрования TLS.',
                  'Приложение имеет цифровую подпись и распространяется исключительно через Google Play Store.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🍎 iOS — Apple App Store',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – инфраструктура Apple',
                  '🏅 SOC 2 Type II – дата-центры Apple',
                  '',
                  'Каждая версия приложения проходит официальную проверку безопасности и качества Apple перед публикацией в App Store.',
                  'Приложение имеет цифровую подпись и распространяется исключительно через Apple App Store.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🔐 Дополнительная защита',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '• Биометрические данные хранятся исключительно в Android Keystore / Apple Secure Enclave – никогда на сервере',
                  '• Максимум 2 устройства на аккаунт – любой несанкционированный доступ автоматически блокируется',
                  '• Push-токены синхронизируются с шифрованием при каждом входе',
                ],
                de: const [
                  'Gemäß den geltenden Datenschutzbestimmungen sind wir verpflichtet, Nutzer klar darüber zu informieren, wie ihre Daten erfasst, gespeichert, verarbeitet und verwendet werden.',
                  '',
                  'Unsere Anwendung basiert auf der Google-Firebase-Plattform, die über folgende internationale Zertifizierungen und Standards verfügt:',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🤖 ANDROID — Google Firebase',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – Informationssicherheitsmanagement',
                  '🏅 ISO 27017 – Sicherheit von Cloud-Diensten',
                  '🏅 ISO 27018 – Schutz personenbezogener Daten in der Cloud',
                  '🏅 SOC 1 / SOC 2 / SOC 3 – Sicherheits- und Verfügbarkeitskontrollen',
                  '',
                  'Alle Daten werden mittels TLS-Verschlüsselung übertragen.',
                  'Die Anwendung ist digital signiert und wird ausschließlich über den Google Play Store vertrieben.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🍎 iOS — Apple App Store',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '🏅 ISO 27001 – Apple-Infrastruktur',
                  '🏅 SOC 2 Type II – Apple-Rechenzentren',
                  '',
                  'Jede Version der App durchläuft vor der Veröffentlichung im App Store die offizielle Sicherheits- und Qualitätsprüfung von Apple.',
                  'Die Anwendung ist digital signiert und wird ausschließlich über den Apple App Store vertrieben.',
                  '',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '🔐 Zusätzlicher Schutz',
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
                  '',
                  '• Biometrische Daten werden ausschließlich im Android Keystore / Apple Secure Enclave gespeichert – niemals auf einem Server',
                  '• Maximal 2 Geräte pro Konto – jeder unbefugte Zugriff wird automatisch blockiert',
                  '• Push-Token werden bei jeder Anmeldung verschlüsselt synchronisiert',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.login,
              title: _tr('secPrijava'),
              content: _content(
                sr: const [
                  'Prijava je jednostavna i bezbedna. Prilikom prvog prijavljivanja automatski se kreira vaš nalog.',
                  '',
                  '• ID broj – vaš jedinstveni identifikacioni broj',
                  '• Serijski broj uređaja – vezan za vaš telefon',
                  '',
                  'Unosom broja telefona sistem vas prepoznaje i omogućava pristup.',
                  '',
                  '🔒 Bezbednost i zaštita podataka',
                  'Naš servis dozvoljava maksimalno 2 uređaja po nalogu. Svaki neovlašćeni pokušaj prijave biće automatski detektovan i BLOKIRAN.',
                ],
                en: const [
                  'Logging in is simple and secure. Your account is created automatically on your first login.',
                  '',
                  '• ID number – your unique identification number',
                  '• Device serial number – linked to your phone',
                  '',
                  'By entering your phone number the system recognizes you and grants access.',
                  '',
                  '🔒 Security and data protection',
                  'Our service allows a maximum of 2 devices per account. Any unauthorized login attempt will be automatically detected and BLOCKED.',
                ],
                ru: const [
                  'Вход в систему прост и безопасен. При первом входе ваш аккаунт создается автоматически.',
                  '',
                  '• ID номер – ваш уникальный идентификационный номер',
                  '• Серийный номер устройства – привязан к вашему телефону',
                  '',
                  'Введя номер телефона, система распознает вас и предоставляет доступ.',
                  '',
                  '🔒 Безопасность и защита данных',
                  'Наш сервис допускает максимум 2 устройства на аккаунт. Любая несанкционированная попытка входа будет автоматически обнаружена и ЗАБЛОКИРОВАНА.',
                ],
                de: const [
                  'Die Anmeldung ist einfach und sicher. Ihr Konto wird bei der ersten Anmeldung automatisch erstellt.',
                  '',
                  '• ID-Nummer – Ihre eindeutige Identifikationsnummer',
                  '• Geräteseriennummer – mit Ihrem Telefon verknüpft',
                  '',
                  'Durch die Eingabe Ihrer Telefonnummer erkennt Sie das System und gewährt Zugang.',
                  '',
                  '🔒 Sicherheit und Datenschutz',
                  'Unser Dienst erlaubt maximal 2 Geräte pro Konto. Jeder unbefugte Anmeldeversuch wird automatisch erkannt und BLOCKIERT.',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.calendar_month,
              title: _tr('secZakazivanje'),
              content: _content(
                sr: const [
                  'Zakazivanje se vrši iz vašeg profila, po danima i gradovima.',
                  '',
                  '• Izaberite dan – radni dani (pon–pet) za tekuću nedelju',
                  '• Izaberite grad – dostupni smerovi: BC i VS',
                  '• Unesite željeno vreme polaska',
                  '• Čekate odgovor – zahtev je u statusu „U obradi"',
                  '',
                  'Status zahteva:',
                  '✅ Odobreno – vožnja je potvrđena',
                  '🔄 Alternativa – ponuđeno drugačije vreme',
                  '❌ Odbijeno – zahtev nije moguće ispuniti',
                  '🚫 Otkazivanje – možete otkazati u bilo kom trenutku',
                  '',
                  'Broj slanja zahteva i otkazivanja je neograničen.',
                  '',
                  'Naš dispečer je potpuno digitalan, automatizovan i nezavistan – radi 24/7 bez ljudske intervencije.',
                  '',
                  '📅 Zakazivanje za sledeću nedelju otvara se automatski u subotu u 03:00 – uz poštovanje svih pravila po tipu putnika.',
                ],
                en: const [
                  'Scheduling is done from your profile, by day and by city.',
                  '',
                  '• Select a day – working days (Mon–Fri) for the current week',
                  '• Select a city – available directions: BC and VS',
                  '• Enter the desired departure time',
                  '• Wait for a response – the request has the status "Processing"',
                  '',
                  'Request status:',
                  '✅ Approved – the ride is confirmed',
                  '🔄 Alternative – a different time was offered',
                  '❌ Rejected – the request cannot be fulfilled',
                  '🚫 Cancellation – you can cancel at any time',
                  '',
                  'The number of requests and cancellations is unlimited.',
                  '',
                  'Our dispatcher is fully digital, automated and independent – it works 24/7 without human intervention.',
                  '',
                  '📅 Scheduling for the next week opens automatically on Saturday at 03:00 – in accordance with all rules per passenger type.',
                ],
                ru: const [
                  'Планирование выполняется из вашего профиля, по дням и городам.',
                  '',
                  '• Выберите день – рабочие дни (пн–пт) текущей недели',
                  '• Выберите город – доступные направления: BC и VS',
                  '• Введите желаемое время отправления',
                  '• Ожидайте ответа – заявка находится в статусе «В обработке»',
                  '',
                  'Статус заявки:',
                  '✅ Одобрено – поездка подтверждена',
                  '🔄 Альтернатива – предложено другое время',
                  '❌ Отклонено – заявку невозможно выполнить',
                  '🚫 Отмена – вы можете отменить в любой момент',
                  '',
                  'Количество заявок и отмен не ограничено.',
                  '',
                  'Наш диспетчер полностью цифровой, автоматизированный и независимый – работает 24/7 без вмешательства человека.',
                  '',
                  '📅 Планирование на следующую неделю открывается автоматически в субботу в 03:00 – с соблюдением всех правил по типу пассажира.',
                ],
                de: const [
                  'Die Terminplanung erfolgt über Ihr Profil, nach Tag und Stadt.',
                  '',
                  '• Wählen Sie einen Tag – Arbeitstage (Mo–Fr) der aktuellen Woche',
                  '• Wählen Sie eine Stadt – verfügbare Richtungen: BC und VS',
                  '• Geben Sie die gewünschte Abfahrtszeit ein',
                  '• Warten Sie auf eine Antwort – die Anfrage hat den Status „In Bearbeitung"',
                  '',
                  'Status der Anfrage:',
                  '✅ Genehmigt – die Fahrt ist bestätigt',
                  '🔄 Alternative – eine andere Zeit wurde angeboten',
                  '❌ Abgelehnt – die Anfrage kann nicht erfüllt werden',
                  '🚫 Stornierung – Sie können jederzeit stornieren',
                  '',
                  'Die Anzahl der Anfragen und Stornierungen ist unbegrenzt.',
                  '',
                  'Unser Dispatcher ist vollständig digital, automatisiert und unabhängig – er arbeitet 24/7 ohne menschliches Eingreifen.',
                  '',
                  '📅 Die Terminplanung für die nächste Woche öffnet automatisch samstags um 03:00 Uhr – unter Einhaltung aller Regeln je Passagiertyp.',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.notifications_active,
              title: _tr('secObavestenja'),
              content: _content(
                sr: const [
                  'Aplikacija vas automatski obaveštava o svakoj promeni statusa:',
                  '',
                  '✅ Odobreno – vožnja je potvrđena',
                  '🔄 Alternativa – ponuđeno je drugačije vreme',
                  '❌ Odbijeno – zahtev nije moguće ispuniti',
                  '🚫 Otkazano – vožnja je otkazana',
                  '',
                  'Obaveštenja stižu i kada je aplikacija zatvorena.',
                ],
                en: const [
                  'The app automatically notifies you of every status change:',
                  '',
                  '✅ Approved – the ride is confirmed',
                  '🔄 Alternative – a different time was offered',
                  '❌ Rejected – the request cannot be fulfilled',
                  '🚫 Canceled – the ride was canceled',
                  '',
                  'Notifications arrive even when the app is closed.',
                ],
                ru: const [
                  'Приложение автоматически уведомляет вас о каждом изменении статуса:',
                  '',
                  '✅ Одобрено – поездка подтверждена',
                  '🔄 Альтернатива – предложено другое время',
                  '❌ Отклонено – заявку невозможно выполнить',
                  '🚫 Отменено – поездка отменена',
                  '',
                  'Уведомления приходят даже когда приложение закрыто.',
                ],
                de: const [
                  'Die App benachrichtigt Sie automatisch über jede Statusänderung:',
                  '',
                  '✅ Genehmigt – die Fahrt ist bestätigt',
                  '🔄 Alternative – eine andere Zeit wurde angeboten',
                  '❌ Abgelehnt – die Anfrage kann nicht erfüllt werden',
                  '🚫 Storniert – die Fahrt wurde storniert',
                  '',
                  'Benachrichtigungen kommen auch an, wenn die App geschlossen ist.',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.fingerprint,
              title: _tr('secBiometrija'),
              content: _content(
                sr: const [
                  'Naš sistem automatski detektuje da li vaš uređaj podržava biometrijsku autentifikaciju (otisak prsta ili Face ID).',
                  '',
                  '• Nema potrebe za bilo kakvim podešavanjem – sve se dešava automatski',
                  '• Pri sledećem otvaranju aplikacije prijava se pokreće sama',
                  '• Vaši biometrijski podaci nikada ne napuštaju vaš uređaj',
                ],
                en: const [
                  'Our system automatically detects whether your device supports biometric authentication (fingerprint or Face ID).',
                  '',
                  '• No setup required – everything happens automatically',
                  '• The login starts by itself the next time you open the app',
                  '• Your biometric data never leaves your device',
                ],
                ru: const [
                  'Наша система автоматически определяет, поддерживает ли ваше устройство биометрическую аутентификацию (отпечаток пальца или Face ID).',
                  '',
                  '• Настройка не требуется – все происходит автоматически',
                  '• При следующем открытии приложения вход выполняется автоматически',
                  '• Ваши биометрические данные никогда не покидают ваше устройство',
                ],
                de: const [
                  'Unser System erkennt automatisch, ob Ihr Gerät die biometrische Authentifizierung (Fingerabdruck oder Face ID) unterstützt.',
                  '',
                  '• Keine Einrichtung erforderlich – alles geschieht automatisch',
                  '• Die Anmeldung startet beim nächsten Öffnen der App von selbst',
                  '• Ihre biometrischen Daten verlassen niemals Ihr Gerät',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.location_on,
              title: _tr('secAdrese'),
              content: _content(
                sr: const [
                  'Svaki putnik ima dodeljenu primarnu adresu za svaki smer (BC / VS).',
                  '',
                  'Ako imate i drugu adresu, možete je izabrati direktno pri zakazivanju – za svaki dan i smer posebno.',
                  '',
                  'Adrese dodeljuje administrator i nisu vidljive drugima.',
                ],
                en: const [
                  'Every passenger has an assigned primary address for each direction (BC / VS).',
                  '',
                  'If you have a second address, you can select it directly while scheduling – separately for each day and direction.',
                  '',
                  'Addresses are assigned by the administrator and are not visible to others.',
                ],
                ru: const [
                  'Каждому пассажиру назначен основной адрес для каждого направления (BC / VS).',
                  '',
                  'Если у вас есть второй адрес, вы можете выбрать его прямо при планировании – отдельно для каждого дня и направления.',
                  '',
                  'Адреса назначаются администратором и не видны другим.',
                ],
                de: const [
                  'Jedem Passagier ist für jede Richtung (BC / VS) eine primäre Adresse zugewiesen.',
                  '',
                  'Wenn Sie eine zweite Adresse haben, können Sie diese direkt bei der Terminplanung auswählen – separat für jeden Tag und jede Richtung.',
                  '',
                  'Adressen werden vom Administrator zugewiesen und sind für andere nicht sichtbar.',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.swap_horiz,
              title: _tr('secAlternativa'),
              content: _content(
                sr: const [
                  'Kada traženo vreme nije dostupno, digitalni dispečer vam može ponuditi alternativu – ranije ili kasnije od traženog termina.',
                  '',
                  'Obaveštenje stiže automatski putem push notifikacije. Nema potrebe da pratite status ručno.',
                ],
                en: const [
                  'When the requested time is not available, the digital dispatcher may offer you an alternative – earlier or later than the requested time.',
                  '',
                  'The notification arrives automatically via push notification. There is no need to check the status manually.',
                ],
                ru: const [
                  'Если запрошенное время недоступно, цифровой диспетчер может предложить вам альтернативу – раньше или позже запрошенного времени.',
                  '',
                  'Уведомление приходит автоматически через push-уведомление. Нет необходимости проверять статус вручную.',
                ],
                de: const [
                  'Wenn die gewünschte Zeit nicht verfügbar ist, kann Ihnen der digitale Dispatcher eine Alternative anbieten – früher oder später als der gewünschte Termin.',
                  '',
                  'Die Benachrichtigung erfolgt automatisch per Push-Benachrichtigung. Der Status muss nicht manuell überprüft werden.',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.event_busy,
              title: _tr('secNeradniDani'),
              content: _content(
                sr: const [
                  'Aplikacija automatski prikazuje obaveštenje ako u tekućoj nedelji postoji neradni dan.',
                  '',
                  'Ti dani nisu dostupni za zakazivanje. Informacija je uvek vidljiva na vašem profilu.',
                ],
                en: const [
                  'The app automatically shows a notice if there is a non-working day in the current week.',
                  '',
                  'Those days are not available for scheduling. The information is always visible on your profile.',
                ],
                ru: const [
                  'Приложение автоматически показывает уведомление, если на текущей неделе есть нерабочий день.',
                  '',
                  'Эти дни недоступны для планирования. Информация всегда отображается в вашем профиле.',
                ],
                de: const [
                  'Die App zeigt automatisch einen Hinweis an, wenn es in der aktuellen Woche einen arbeitsfreien Tag gibt.',
                  '',
                  'Diese Tage stehen nicht zur Terminplanung zur Verfügung. Die Information ist immer in Ihrem Profil sichtbar.',
                ],
              ),
            ),
            _HelpSection(
              icon: Icons.people,
              title: _tr('secTipoviPutnika'),
              content: _content(
                sr: const [
                  '👷 Radnik',
                  'Radnici uglavnom imaju slicna polazna vremena - bez potrebe za dodatnim preslagivanjem termina. Prolaze standardnu obradu zahteva.',
                  '',
                  '🎒 Učenik',
                  '• Do 16h prijaviti željeni polazak za sutrašnji dan',
                  '• Svim učenicima koji se prijave na vreme garantujemo željeni termin',
                  '• Prijave posle 16h se primaju, ali ne možemo garantovati željeni polazak',
                  '• Svaka izmena prolazi ponovnu obradu zahteva uz usklađivanje kapaciteta digitalnog dispečera kako bi sistem bio uvek 100% tacan.',
                  '',
                  '🗓️ Dnevni putnik',
                  'Dnevni putnici zakazuju posle 16h, nakon radnika i učenika, u pravičnom toku obrade kod digitalnog dispečera.',
                  '',
                  '⏱️ Važi za sve tipove putnika',
                  'Rok za javljanje je 15 minuta pre polaska, kako bi digitalni dispečer imao dovoljno vremena da obradi sve pristigle zahteve i pravilno rasporedi putnike.',
                ],
                en: const [
                  '👷 Worker',
                  'Workers usually have similar departure times – no need for additional schedule adjustments. They go through standard request processing.',
                  '',
                  '🎒 Student',
                  '• Report the desired departure for the next day by 4 PM',
                  '• We guarantee the desired time slot to all students who apply on time',
                  '• Applications after 4 PM are accepted, but we cannot guarantee the desired departure',
                  '• Every change goes through re-processing along with capacity alignment by the digital dispatcher, so the system remains 100% accurate.',
                  '',
                  '🗓️ Daily passenger',
                  'Daily passengers schedule after 4 PM, after workers and students, in a fair processing order by the digital dispatcher.',
                  '',
                  '⏱️ Applies to all passenger types',
                  'The deadline for check-in is 15 minutes before departure, so the digital dispatcher has enough time to process all incoming requests and properly arrange passengers.',
                ],
                ru: const [
                  '👷 Рабочий',
                  'У рабочих обычно похожее время отправления – нет необходимости в дополнительной корректировке расписания. Проходят стандартную обработку заявок.',
                  '',
                  '🎒 Ученик',
                  '• Сообщите желаемое время отправления на следующий день до 16:00',
                  '• Мы гарантируем желаемое время всем ученикам, подавшим заявку вовремя',
                  '• Заявки после 16:00 принимаются, но мы не можем гарантировать желаемое время отправления',
                  '• Каждое изменение проходит повторную обработку с согласованием вместимости цифровым диспетчером, чтобы система всегда оставалась 100% точной.',
                  '',
                  '🗓️ Ежедневный пассажир',
                  'Ежедневные пассажиры планируют поездку после 16:00, после рабочих и учеников, в порядке справедливой обработки цифровым диспетчером.',
                  '',
                  '⏱️ Применимо ко всем типам пассажиров',
                  'Крайний срок регистрации – 15 минут до отправления, чтобы у цифрового диспетчера было достаточно времени обработать все поступившие заявки и правильно распределить пассажиров.',
                ],
                de: const [
                  '👷 Arbeiter',
                  'Arbeiter haben in der Regel ähnliche Abfahrtszeiten – keine zusätzliche Terminanpassung erforderlich. Sie durchlaufen die Standardbearbeitung der Anfragen.',
                  '',
                  '🎒 Schüler',
                  '• Die gewünschte Abfahrt für den nächsten Tag bis 16 Uhr melden',
                  '• Wir garantieren allen Schülern, die sich rechtzeitig anmelden, den gewünschten Zeitraum',
                  '• Anmeldungen nach 16 Uhr werden angenommen, aber wir können die gewünschte Abfahrt nicht garantieren',
                  '• Jede Änderung durchläuft eine erneute Bearbeitung zusammen mit der Kapazitätsabstimmung durch den digitalen Dispatcher, damit das System immer zu 100 % genau bleibt.',
                  '',
                  '🗓️ Tagespassagier',
                  'Tagespassagiere planen nach 16 Uhr, nach den Arbeitern und Schülern, in einer fairen Bearbeitungsreihenfolge durch den digitalen Dispatcher.',
                  '',
                  '⏱️ Gilt für alle Passagiertypen',
                  'Die Frist für die Anmeldung beträgt 15 Minuten vor Abfahrt, damit der digitale Dispatcher genügend Zeit hat, alle eingehenden Anfragen zu bearbeiten und die Passagiere richtig einzuteilen.',
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<String> _content({
    required List<String> sr,
    required List<String> en,
    required List<String> ru,
    required List<String> de,
  }) {
    switch (V3LocaleManager().currentLocale.languageCode) {
      case 'en':
        return en;
      case 'ru':
        return ru;
      case 'de':
        return de;
      default:
        return sr;
    }
  }
}

class _HelpSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final List<String> content;

  const _HelpSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  State<_HelpSection> createState() => _HelpSectionState();
}

class _HelpSectionState extends State<_HelpSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      margin: const EdgeInsets.only(bottom: 10),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Icon(widget.icon, color: Colors.white70, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 12),
                ...widget.content.map(
                  (line) => line.isEmpty
                      ? const SizedBox(height: 6)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            line,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
