import 'package:flutter/material.dart';

import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

class V3HelpScreen extends StatelessWidget {
  const V3HelpScreen({super.key});

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
          title: const Text(
            '❓ Uputstvo za korišćenje',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _HelpSection(
              icon: Icons.login,
              title: '1. Prijava (Log in)',
              content: [
                'Prijava je jednostavna i bezbedna. Prilikom prvog prijavljivanja automatski se kreira vaš nalog.',
                '',
                '• ID broj – vaš jedinstveni identifikacioni broj',
                '• Serijski broj uređaja – vezan za vaš telefon',
                '',
                'Unosom broja telefona sistem vas prepoznaje i omogućava pristup.',
                '',
                '🔒 Bezbednost i zaštita podataka',
                'Naš sertifikovani servis dozvoljava maksimalno 2 uređaja po nalogu. Svaki neovlašćeni pokušaj prijave biće automatski detektovan i zabeležen.',
              ],
            ),
            _HelpSection(
              icon: Icons.calendar_month,
              title: '2. Zakazivanje prevoza',
              content: [
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
            ),
            _HelpSection(
              icon: Icons.notifications_active,
              title: '3. Obaveštenja (Push notifikacije)',
              content: [
                'Aplikacija vas automatski obaveštava o svakoj promeni statusa:',
                '',
                '✅ Odobreno – vožnja je potvrđena',
                '🔄 Alternativa – ponuđeno je drugačije vreme',
                '❌ Odbijeno – zahtev nije moguće ispuniti',
                '🚫 Otkazano – vožnja je otkazana',
                '',
                'Obaveštenja stižu i kada je aplikacija zatvorena.',
              ],
            ),
            _HelpSection(
              icon: Icons.fingerprint,
              title: '4. Biometrijska prijava',
              content: [
                'Naš sistem automatski detektuje da li vaš uređaj podržava biometrijsku autentifikaciju (otisak prsta ili Face ID).',
                '',
                '• Nema potrebe za bilo kakvim podešavanjem – sve se dešava automatski',
                '• Pri sledećem otvaranju aplikacije prijava se pokreće sama',
                '• Vaši biometrijski podaci nikada ne napuštaju vaš uređaj',
              ],
            ),
            _HelpSection(
              icon: Icons.location_on,
              title: '5. Adrese',
              content: [
                'Svaki putnik ima dodeljenu primarnu adresu za svaki smer (BC / VS).',
                '',
                'Ako imate i drugu adresu, možete je izabrati direktno pri zakazivanju – za svaki dan i smer posebno.',
                '',
                'Adrese dodeljuje administrator i nisu vidljive drugima.',
              ],
            ),
            _HelpSection(
              icon: Icons.swap_horiz,
              title: '6. Alternativni termin',
              content: [
                'Kada traženo vreme nije dostupno, digitalni dispečer vam može ponuditi alternativu – ranije ili kasnije od traženog termina.',
                '',
                'Obaveštenje stiže automatski putem push notifikacije. Nema potrebe da pratite status ručno.',
              ],
            ),
            _HelpSection(
              icon: Icons.event_busy,
              title: '7. Neradni dani',
              content: [
                'Aplikacija automatski prikazuje obaveštenje ako u tekućoj nedelji postoji neradni dan.',
                '',
                'Ti dani nisu dostupni za zakazivanje. Informacija je uvek vidljiva na vašem profilu.',
              ],
            ),
            _HelpSection(
              icon: Icons.verified_user,
              title: '8. Bezbednost i sertifikati',
              content: [
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
            ),
            _HelpSection(
              icon: Icons.people,
              title: '9. Tipovi putnika',
              content: [
                '👷 Radnik',
                'Radnici imaju stalna polazna vremena – bez potrebe za dodatnim zakazivanjem. Sistem automatski obrađuje njihove termine.',
                '',
                '🎒 Učenik',
                '• Do 16h prijaviti željeni polazak za sutrašnji dan',
                '• Svim učenicima koji se prijave na vreme garantujemo željeni termin',
                '• Prijave posle 16h se primaju, ali ne možemo garantovati željeni polazak',
                '• Svaka izmena prolazi kroz ponovnu obradu dispečera – sistem je uvek 100% tačan',
                '• Najkasnije javljanje je 15 minuta pre polaska',
                '',
                '🗓️ Dnevni putnik',
                'Dnevni putnici zakazuju posle 16h, nakon radnika i učenika, u pravičnom toku obrade kod digitalnog dispečera.',
              ],
            ),
          ],
        ),
      ),
    );
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
                  Icon(widget.icon, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                    size: 20,
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
