import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../models/registrovani_putnik.dart';
import '../services/adresa_supabase_service.dart';
import '../services/registrovani_putnik_service.dart';
import '../services/voznje_log_service.dart'; // 📝 DODATO
import '../theme.dart';
import '../utils/app_snack_bar.dart';

/// UNIFIKOVANI WIDGET ZA DODAVANJE I EDITOVANJE MESEČNIH PUTNIKA
///
/// Kombinuje funkcionalnost iz add_registrovani_putnik_dialog.dart i edit_registrovani_putnik_dialog.dart
/// u jedan optimizovan widget koji radi i za dodavanje i za editovanje.
///
/// Parametri:
/// - existingPutnik: null za dodavanje, postojeći objekat za editovanje
/// - onSaved: callback koji se poziva posle uspešnog čuvanja
class RegistrovaniPutnikDialog extends StatefulWidget {
  final RegistrovaniPutnik? existingPutnik; // null = dodavanje, !null = editovanje
  final VoidCallback? onSaved;

  const RegistrovaniPutnikDialog({
    super.key,
    this.existingPutnik,
    this.onSaved,
  });

  /// Da li je dialog u edit modu
  bool get isEditing => existingPutnik != null;

  @override
  State<RegistrovaniPutnikDialog> createState() => _RegistrovaniPutnikDialogState();
}

class _RegistrovaniPutnikDialogState extends State<RegistrovaniPutnikDialog> {
  final RegistrovaniPutnikService _registrovaniPutnikService = RegistrovaniPutnikService();

  // Form controllers
  final TextEditingController _imeController = TextEditingController();
  final TextEditingController _tipSkoleController = TextEditingController();
  final TextEditingController _brojTelefonaController = TextEditingController();
  final TextEditingController _brojTelefona2Controller = TextEditingController();
  final TextEditingController _brojTelefonaOcaController = TextEditingController();
  final TextEditingController _brojTelefonaMajkeController = TextEditingController();
  final TextEditingController _adresaBelaCrkvaController = TextEditingController();
  final TextEditingController _adresaVrsacController = TextEditingController();
  final TextEditingController _brojMestaController = TextEditingController();
  final TextEditingController _cenaPoDanuController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  // 🧾 Kontroleri za podatke o firmi (račun)
  final TextEditingController _firmaNazivController = TextEditingController();
  final TextEditingController _firmaPibController = TextEditingController();
  final TextEditingController _firmaMbController = TextEditingController();
  final TextEditingController _firmaZiroController = TextEditingController();
  final TextEditingController _firmaAdresaController = TextEditingController();
  bool _trebaRacun = false;
  // Selected address UUIDs (keeps track when user chooses a suggestion)
  String? _adresaBelaCrkvaId;
  String? _adresaVrsacId;

  // Liste odobrenih adresa za dropdown
  List<Map<String, String>> _adreseBelaCrkva = [];
  List<Map<String, String>> _adreseVrsac = [];

  // Form data
  String _tip = 'radnik';

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAdreseFromDatabase();
    _loadDataFromExistingPutnik();
  }

  /// Učitaj odobrene adrese iz baze
  Future<void> _loadAdreseFromDatabase() async {
    try {
      final adreseBC = await AdresaSupabaseService.getAdreseZaGrad('BC');
      final adreseVS = await AdresaSupabaseService.getAdreseZaGrad('VS');

      if (mounted) {
        setState(() {
          _adreseBelaCrkva = adreseBC.map((a) => {'id': a.id, 'naziv': a.naziv}).toList()
            ..sort((a, b) => _serbianCompare(a['naziv'] ?? '', b['naziv'] ?? ''));
          _adreseVrsac = adreseVS.map((a) => {'id': a.id, 'naziv': a.naziv}).toList()
            ..sort((a, b) => _serbianCompare(a['naziv'] ?? '', b['naziv'] ?? ''));
        });
      }
    } catch (e) {
      // Error loading addresses
    }
  }

  /// 🔤 Srpsko sortiranje - pravilno sortira č, ć, š, ž, đ
  int _serbianCompare(String a, String b) {
    // Normalizuj za sortiranje: zameni srpske karaktere
    String normalize(String s) {
      return s
          .toLowerCase()
          .replaceAll('č', 'c~')
          .replaceAll('ć', 'c~~')
          .replaceAll('đ', 'd~')
          .replaceAll('š', 's~')
          .replaceAll('ž', 'z~');
    }

    return normalize(a).compareTo(normalize(b));
  }

  void _loadDataFromExistingPutnik() async {
    if (widget.isEditing) {
      final putnik = widget.existingPutnik!;

      // Load basic info
      _imeController.text = putnik.putnikIme;
      _tip = putnik.tip;
      _brojMestaController.text = putnik.brojMesta.toString();
      _tipSkoleController.text = putnik.tipSkole ?? '';
      _brojTelefonaController.text = putnik.brojTelefona ?? '';
      _brojTelefona2Controller.text = putnik.brojTelefona2 ?? '';
      _brojTelefonaOcaController.text = putnik.brojTelefonaOca ?? '';
      _brojTelefonaMajkeController.text = putnik.brojTelefonaMajke ?? '';

      // Load cena po danu
      if (putnik.cenaPoDanu != null && putnik.cenaPoDanu! > 0) {
        _cenaPoDanuController.text = putnik.cenaPoDanu!.toStringAsFixed(0);
      }

      // 📧 Load email
      _emailController.text = putnik.email ?? '';

      // 🧾 Load podaci za račun
      _trebaRacun = putnik.trebaRacun;
      _firmaNazivController.text = putnik.firmaNaziv ?? '';
      _firmaPibController.text = putnik.firmaPib ?? '';
      _firmaMbController.text = putnik.firmaMb ?? '';
      _firmaZiroController.text = putnik.firmaZiro ?? '';
      _firmaAdresaController.text = putnik.firmaAdresa ?? '';

      // Load addresses asynchronously
      _loadAdreseForEditovanje();
    } else {
      // Default za novog putnika
      _brojMestaController.text = '1';
    }
  }

  Future<void> _loadAdreseForEditovanje() async {
    // Load existing address names for the edit dialog using the UUIDs
    final putnik = widget.existingPutnik;
    if (putnik == null) return;

    // Try batch fetch for both ids
    try {
      final idsToFetch = <String>[];
      if (putnik.adresaBelaCrkvaId != null && putnik.adresaBelaCrkvaId!.isNotEmpty) {
        idsToFetch.add(putnik.adresaBelaCrkvaId!);
      }
      if (putnik.adresaVrsacId != null && putnik.adresaVrsacId!.isNotEmpty) {
        idsToFetch.add(putnik.adresaVrsacId!);
      }

      if (idsToFetch.isNotEmpty) {
        final fetched = await AdresaSupabaseService.getAdreseByUuids(idsToFetch);

        final bcNaziv = putnik.adresaBelaCrkvaId != null
            ? fetched[putnik.adresaBelaCrkvaId!]?.naziv ??
                await AdresaSupabaseService.getNazivAdreseByUuid(putnik.adresaBelaCrkvaId)
            : null;

        final vsNaziv = putnik.adresaVrsacId != null
            ? fetched[putnik.adresaVrsacId!]?.naziv ??
                await AdresaSupabaseService.getNazivAdreseByUuid(putnik.adresaVrsacId)
            : null;

        if (mounted) {
          setState(() {
            _adresaBelaCrkvaController.text = bcNaziv ?? '';
            _adresaVrsacController.text = vsNaziv ?? '';
            // keep UUIDs so autocomplete selection is preserved
            _adresaBelaCrkvaId = putnik.adresaBelaCrkvaId;
            _adresaVrsacId = putnik.adresaVrsacId;
          });
        }
      } else {
        // No UUIDs present → leave controllers empty
        if (mounted) {
          setState(() {
            _adresaBelaCrkvaController.text = '';
            _adresaVrsacController.text = '';
            _adresaBelaCrkvaId = null;
            _adresaVrsacId = null;
          });
        }
      }
    } catch (e) {
      // In case of any error, keep empty strings but don't crash the dialog
      if (mounted) {
        setState(() {
          _adresaBelaCrkvaController.text = '';
          _adresaVrsacController.text = '';
        });
      }
    }
  }

  @override
  void dispose() {
    try {
      _imeController.dispose();
      _tipSkoleController.dispose();
      _brojTelefonaController.dispose();
      _brojTelefona2Controller.dispose();
      _brojTelefonaOcaController.dispose();
      _brojTelefonaMajkeController.dispose();
      _adresaBelaCrkvaController.dispose();
      _adresaVrsacController.dispose();
      _brojMestaController.dispose();
      _cenaPoDanuController.dispose();
      _emailController.dispose();
      _firmaNazivController.dispose();
      _firmaPibController.dispose();
      _firmaMbController.dispose();
      _firmaZiroController.dispose();
      _firmaAdresaController.dispose();

      super.dispose();
    } catch (e) {
      debugPrint('🔴 Error disposing RegistrovaniPutnikDialog: $e');
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 📱 Izračunaj dostupnu visinu uzimajući u obzir tastaturу
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = screenHeight - keyboardHeight;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: keyboardHeight > 0 ? 8 : 24, // Manji padding kad je tastatura otvorena
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: keyboardHeight > 0
              ? availableHeight * 0.95 // Kad je tastatura - koristi skoro svu dostupnu visinu
              : screenHeight * 0.85, // Kad nema tastature - standardno
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).glassBorder,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: _buildContent(),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = widget.isEditing ? '🔧 Uredi putnika' : '✨ Dodaj putnika';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).glassContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).glassBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                color: Colors.white,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.red.withOpacity(0.4),
                ),
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      dragStartBehavior: DragStartBehavior.down, // Omogući long press na child widgetima
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBasicInfoSection(),
          const SizedBox(height: 20),
          _buildContactSection(),
          const SizedBox(height: 20),
          _buildAddressSection(),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return _buildGlassSection(
      title: 'Osnovne informacije',
      child: Column(
        children: [
          _buildTextField(
            controller: _imeController,
            label: 'Ime i prezime',
            icon: Icons.person,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ime je obavezno polje';
              }
              if (value.trim().length < 2) {
                return 'Ime mora imati najmanje 2 karaktera';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildDropdown(
            value: _tip,
            label: 'Tip putnika',
            icon: Icons.category,
            items: const ['radnik', 'ucenik', 'dnevni', 'posiljka'],
            onChanged: (value) => setState(() => _tip = value ?? 'radnik'),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _brojMestaController,
            label: 'Broj mesta (kapacitet)',
            icon: Icons.event_seat,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Unesite broj mesta';
              final n = int.tryParse(value);
              if (n == null || n < 1) return 'Broj mesta mora biti veći od 0';
              return null;
            },
          ),
          if (_tip == 'ucenik') ...[
            const SizedBox(height: 24),
            _buildTextField(
              controller: _tipSkoleController,
              label: 'Škola',
              icon: Icons.school,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return _buildGlassSection(
      title: '📱 Kontakt informacije',
      child: Column(
        children: [
          _buildPhoneFieldWithContactPicker(
            controller: _brojTelefonaController,
            label: _tip == 'ucenik' ? 'Broj telefona učenika' : 'Broj telefona',
            icon: Icons.phone,
          ),
          const SizedBox(height: 12),
          // Drugi broj telefona za sve tipove
          _buildPhoneFieldWithContactPicker(
            controller: _brojTelefona2Controller,
            label: 'Drugi broj telefona (opciono)',
            icon: Icons.phone_android,
          ),
          if (_tip == 'ucenik') ...[
            const SizedBox(height: 16),
            // Glassmorphism container za roditeljske kontakte
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.family_restroom,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kontakt podaci roditelja',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontSize: 14,
                                shadows: [
                                  Shadow(
                                    offset: const Offset(1, 1),
                                    blurRadius: 3,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPhoneFieldWithContactPicker(
                    controller: _brojTelefonaOcaController,
                    label: 'Broj telefona oca',
                    icon: Icons.man,
                  ),
                  const SizedBox(height: 12),
                  _buildPhoneFieldWithContactPicker(
                    controller: _brojTelefonaMajkeController,
                    label: 'Broj telefona majke',
                    icon: Icons.woman,
                  ),
                ],
              ),
            ),
          ],
          // Cena po danu sekcija - VIDLJIVA ZA SVE TIPOVE (učenik, radnik, dnevni)
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.attach_money, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cena obračuna (obavezno)',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Unesite cenu po danu za obračun. Ova cena će se koristiti za naplatu usluga.\n• Radnik/Učenik: naplata po danu.\n• Dnevni/Pošiljka: naplata po svakom pokupljenju.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cenaPoDanuController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Iznos za obračun (RSD)',
                    hintText: 'npr. 500',
                    prefixIcon: const Icon(Icons.payments),
                    suffixText: 'RSD',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Cena obračuna je obavezna';
                    }
                    final cena = double.tryParse(value);
                    if (cena == null || cena <= 0) {
                      return 'Unesite validan iznos veći od 0';
                    }
                    return null;
                  },
                  style: const TextStyle(color: Colors.black),
                ),
                const SizedBox(height: 16),
                // 📧 EMAIL POLJE
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email (opciono)',
                    hintText: 'npr. putnik@email.com',
                    prefixIcon: const Icon(Icons.email),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(color: Colors.black),
                ),
                const SizedBox(height: 16),
                // 🧾 CHECKBOX ZA RAČUN
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _trebaRacun ? Colors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _trebaRacun ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.receipt_long,
                            color: _trebaRacun ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Treba račun na kraju meseca',
                              style: TextStyle(
                                color: _trebaRacun ? Colors.green : Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Switch(
                            value: _trebaRacun,
                            thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.green;
                              }
                              return null;
                            }),
                            onChanged: (value) {
                              setState(() {
                                _trebaRacun = value;
                              });
                              if (value) {
                                _showFirmaDialog();
                              }
                            },
                          ),
                        ],
                      ),
                      if (_trebaRacun && _firmaNazivController.text.isNotEmpty) ...[
                        const Divider(color: Colors.white24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_firmaNazivController.text}\nPIB: ${_firmaPibController.text}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                              onPressed: _showFirmaDialog,
                              tooltip: 'Uredi podatke firme',
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 🧾 Popup za unos podataka firme
  void _showFirmaDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.business, color: Colors.green),
            const SizedBox(width: 8),
            const Text('Podaci firme za račun'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _firmaNazivController,
                decoration: const InputDecoration(
                  labelText: 'Naziv firme *',
                  hintText: 'npr. PR Optičarska radnja MAZA',
                  prefixIcon: Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _firmaPibController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIB *',
                  hintText: '111394041',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _firmaMbController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Matični broj',
                  hintText: '65380200',
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _firmaZiroController,
                decoration: const InputDecoration(
                  labelText: 'Žiro račun',
                  hintText: '340-0000011427591-61',
                  prefixIcon: Icon(Icons.account_balance),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _firmaAdresaController,
                decoration: const InputDecoration(
                  labelText: 'Adresa firme',
                  hintText: 'Ulica i broj, grad',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Otkaži'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              if (_firmaNazivController.text.trim().isEmpty || _firmaPibController.text.trim().isEmpty) {
                AppSnackBar.warning(dialogContext, 'Unesite naziv firme i PIB');
                return;
              }
              Navigator.pop(dialogContext);
              setState(() {}); // Refresh UI
            },
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    return _buildGlassSection(
      title: '🏠 Adrese',
      child: Column(
        children: [
          // DROPDOWN ZA BELA CRKVA
          DropdownButtonFormField<String>(
            key: ValueKey('bc_$_adresaBelaCrkvaId'),
            value: _adreseBelaCrkva.any((a) => a['id'] == _adresaBelaCrkvaId) ? _adresaBelaCrkvaId : null,
            decoration: InputDecoration(
              labelText: 'Adresa Bela Crkva',
              prefixIcon: const Icon(Icons.location_on),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: const TextStyle(color: Colors.black),
            isExpanded: true,
            hint: const Text('Izaberi adresu...', style: TextStyle(color: Colors.grey)),
            items: [
              ..._adreseBelaCrkva.map((adresa) => DropdownMenuItem<String>(
                    value: adresa['id'],
                    child: Text(adresa['naziv'] ?? ''),
                  )),
            ],
            onChanged: (value) {
              setState(() {
                _adresaBelaCrkvaId = value;
                _adresaBelaCrkvaController.text =
                    _adreseBelaCrkva.firstWhere((a) => a['id'] == value, orElse: () => {'naziv': ''})['naziv'] ?? '';
              });
            },
          ),
          const SizedBox(height: 12),
          // DROPDOWN ZA Vrsac
          DropdownButtonFormField<String>(
            key: ValueKey('vs_$_adresaVrsacId'),
            value: _adreseVrsac.any((a) => a['id'] == _adresaVrsacId) ? _adresaVrsacId : null,
            decoration: InputDecoration(
              labelText: 'Adresa Vrsac',
              prefixIcon: const Icon(Icons.location_city),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: const TextStyle(color: Colors.black),
            isExpanded: true,
            hint: const Text('Izaberi adresu...', style: TextStyle(color: Colors.grey)),
            items: [
              ..._adreseVrsac.map((adresa) => DropdownMenuItem<String>(
                    value: adresa['id'],
                    child: Text(adresa['naziv'] ?? ''),
                  )),
            ],
            onChanged: (value) {
              setState(() {
                _adresaVrsacId = value;
                _adresaVrsacController.text =
                    _adreseVrsac.firstWhere((a) => a['id'] == value, orElse: () => {'naziv': ''})['naziv'] ?? '';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final buttonText = widget.isEditing ? 'Sačuvaj' : 'Dodaj';
    final buttonIcon = widget.isEditing ? Icons.save : Icons.add_circle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).glassContainer,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).glassBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          // Cancel button
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.red.withOpacity(0.4),
                ),
              ),
              child: TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: const Text(
                  'Otkaži',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    shadows: [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 3,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          // Save/Add button
          Expanded(
            flex: 2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.green.withOpacity(0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _savePutnik,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black54,
                                  offset: Offset(1, 1),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            child: Text(
                              widget.isEditing ? 'Čuva...' : 'Dodaje...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            buttonIcon,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 1),
                                  blurRadius: 3,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSection({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).glassContainer,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Theme.of(context).glassBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.black87),
      validator: validator,
      enableInteractiveSelection: true,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        hintText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        prefixIcon: icon != null ? Icon(icon, color: Colors.blue, size: 20) : null,
        fillColor: Colors.white.withOpacity(0.9),
        filled: true,
      ),
    );
  }

  /// 📇 Polje za telefon sa dugmetom za biranje iz imenika
  Widget _buildPhoneFieldWithContactPicker({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.black87),
            enableInteractiveSelection: true,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: label,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
              prefixIcon: Icon(icon, color: Colors.blue, size: 20),
              fillColor: Colors.white.withOpacity(0.9),
              filled: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 📇 Dugme za biranje iz imenika
        Material(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              try {
                // First check current permission status
                final status = await Permission.contacts.status;
                if (status.isGranted || status.isLimited) {
                  // Permission already granted, get contacts
                  final contacts = await FlutterContacts.getContacts(withProperties: true);
                  if (contacts.isEmpty) {
                    if (mounted) {
                      AppSnackBar.warning(context, 'Nema kontakata u imeniku');
                    }
                    return;
                  }
                  // Show contact list
                  if (mounted) {
                    _showContactPickerDialog(context, contacts, controller);
                  }
                } else if (status.isPermanentlyDenied) {
                  // Permission permanently denied, show settings dialog
                  if (mounted) {
                    _showPermissionSettingsDialog(context);
                  }
                } else {
                  // Request permission
                  final permission = await FlutterContacts.requestPermission();
                  if (permission) {
                    // Get all contacts
                    final contacts = await FlutterContacts.getContacts(withProperties: true);

                    if (contacts.isEmpty) {
                      if (mounted) {
                        AppSnackBar.warning(context, 'Nema kontakata u imeniku');
                      }
                      return;
                    }

                    // Show contact list
                    if (mounted) {
                      _showContactPickerDialog(context, contacts, controller);
                    }
                  } else {
                    if (mounted) {
                      AppSnackBar.warning(context, 'Dozvola za pristup kontaktima je odbijena');
                    }
                  }
                }
              } catch (e) {
                if (mounted) {
                  AppSnackBar.error(context, 'Greška pri izboru kontakta: $e');
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.contacts,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      style: const TextStyle(color: Colors.black87),
      decoration: InputDecoration(
        hintText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        prefixIcon: Icon(icon, color: Colors.blue, size: 20),
        fillColor: Colors.white.withOpacity(0.9),
        filled: true,
      ),
      dropdownColor: Theme.of(context).colorScheme.surface,
      items: items.map((String item) {
        // Mapiranje internih vrednosti u lepše labele za prikaz
        String displayLabel = item;
        switch (item) {
          case 'radnik':
            displayLabel = 'Radnik';
            break;
          case 'ucenik':
            displayLabel = 'Učenik';
            break;
          case 'dnevni':
            displayLabel = 'Dnevni';
            break;
          case 'posiljka':
            displayLabel = 'Pošiljka';
            break;
        }

        return DropdownMenuItem<String>(
          value: item,
          child: Text(
            displayLabel,
            style: const TextStyle(color: Colors.black87),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  String? _validateForm() {
    final ime = _imeController.text.trim();
    if (ime.isEmpty) {
      return 'Ime putnika je obavezno';
    }
    if (ime.length < 2) {
      return 'Ime putnika mora imati najmanje 2 karaktera';
    }

    // 📱 Validacija broja telefona
    final telefon = _brojTelefonaController.text.trim();
    if (telefon.isEmpty) {
      return 'Broj telefona je obavezan';
    }

    final telefonError = _validatePhoneNumber(telefon);
    if (telefonError != null) {
      return telefonError;
    }

    return null;
  }

  /// 📱 Validacija formata srpskog broja telefona
  String? _validatePhoneNumber(String telefon) {
    // Ukloni razmake, crtice, zagrade
    final cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Dozvoljeni formati:
    // 06x xxx xxxx (10 cifara)
    // +381 6x xxx xxxx (12-13 cifara sa +381)
    // 00381 6x xxx xxxx (13-14 cifara sa 00381)

    if (cleaned.startsWith('+381')) {
      final localPart = cleaned.substring(4);
      if (localPart.length < 8 || localPart.length > 10) {
        return 'Neispravan format broja (+381 6x xxx xxxx)';
      }
      if (!localPart.startsWith('6')) {
        return 'Mobilni broj mora počinjati sa 6 posle +381';
      }
    } else if (cleaned.startsWith('00381')) {
      final localPart = cleaned.substring(5);
      if (localPart.length < 8 || localPart.length > 10) {
        return 'Neispravan format broja (00381 6x xxx xxxx)';
      }
      if (!localPart.startsWith('6')) {
        return 'Mobilni broj mora počinjati sa 6 posle 00381';
      }
    } else if (cleaned.startsWith('06')) {
      if (cleaned.length < 9 || cleaned.length > 10) {
        return 'Broj mora imati 9-10 cifara (06x xxx xxxx)';
      }
    } else {
      return 'Broj mora počinjati sa 06, +381 ili 00381';
    }

    // Proveri da su sve ostale cifre
    final digitsOnly = cleaned.replaceAll('+', '');
    if (!RegExp(r'^\d+$').hasMatch(digitsOnly)) {
      return 'Broj telefona može sadržati samo cifre';
    }

    return null;
  }

  /// 📱 Provera da li broj telefona već postoji u bazi
  Future<String?> _checkDuplicatePhone() async {
    final telefon = _brojTelefonaController.text.trim();
    if (telefon.isEmpty) return null;

    // Normalizuj broj za poređenje (ukloni +381, 00381, vodeću 0)
    final normalized = _normalizePhoneNumber(telefon);

    try {
      final response =
          await supabase.from('registrovani_putnici').select('id, putnik_ime, broj_telefona').eq('obrisan', false);

      for (final row in response as List) {
        final existingPhone = row['broj_telefona'] as String?;
        if (existingPhone == null) continue;

        final existingNormalized = _normalizePhoneNumber(existingPhone);

        // Ako je isti broj, a nije isti putnik (za edit mode)
        if (existingNormalized == normalized) {
          final existingId = row['id'] as String;
          if (widget.isEditing && widget.existingPutnik?.id == existingId) {
            continue; // Isti putnik, OK
          }
          final existingName = row['putnik_ime'] as String? ?? 'Nepoznat';
          return 'Broj telefona već koristi putnik: $existingName';
        }
      }
    } catch (e) {
      // Ako ne možemo proveriti, nastavi (bolje nego blokirati)
    }

    return null;
  }

  /// Normalizuje broj telefona za poređenje
  String _normalizePhoneNumber(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Ukloni prefix i vrati samo lokalni deo
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }

    return cleaned;
  }

  Future<void> _savePutnik() async {
    final validationError = _validateForm();
    if (validationError != null) {
      AppSnackBar.warning(context, validationError);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 📱 Provera duplikata broja telefona
      final duplicateError = await _checkDuplicatePhone();
      if (duplicateError != null) {
        if (mounted) {
          AppSnackBar.warning(context, duplicateError);
        }
        setState(() => _isLoading = false);
        return;
      }

      final putnikData = _preparePutnikData();

      if (widget.isEditing) {
        await _registrovaniPutnikService.updateRegistrovaniPutnik(
          widget.existingPutnik!.id,
          putnikData,
        );
      } else {
        await _registrovaniPutnikService.dodajMesecnogPutnika(
          RegistrovaniPutnik.fromMap(putnikData),
        );
      }

      if (mounted) {
        // Sačuvaj parent context PRE pop-a (dijalog context postaje invalid nakon pop-a)
        final parentContext = Navigator.of(context).context;
        Navigator.of(context).pop();
        if (widget.onSaved != null) widget.onSaved!();
        if (parentContext.mounted) {
          AppSnackBar.success(parentContext, '✅ Putnik uspešno sačuvan!');
        }
      }
    } catch (e) {
      debugPrint('❌ Greška pri čuvanju putnika: $e');

      // 📝 LOG GRESKE ZA ADMINA
      try {
        await VoznjeLogService.logGreska(
          putnikId: widget.existingPutnik?.id,
          greska: '[$_tip | ${_imeController.text}] ${e.toString()}',
        );
      } catch (e) {
        debugPrint('⚠️ Error logging user action: $e');
      }

      if (mounted) {
        var errorMsg = e.toString();
        if (errorMsg.contains('Exception:')) {
          errorMsg = errorMsg.split('Exception:').last.trim();
        }
        AppSnackBar.error(context, 'Greška: $errorMsg');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _preparePutnikData() {
    final now = DateTime.now();
    // Default datumi ako nedostaju
    final pocetak = widget.existingPutnik?.datumPocetkaMeseca ?? DateTime(now.year, now.month);
    final kraj = widget.existingPutnik?.datumKrajaMeseca ?? DateTime(now.year, now.month + 1, 0);

    return {
      'id': widget.existingPutnik?.id, // Može biti null za novi insert
      'putnik_ime': _imeController.text.trim(),
      'tip': _tip,
      'broj_mesta': int.tryParse(_brojMestaController.text) ?? 1,
      'tip_skole': _tipSkoleController.text.isEmpty ? null : _tipSkoleController.text.trim(),
      'broj_telefona': _brojTelefonaController.text.isEmpty ? null : _brojTelefonaController.text.trim(),
      'broj_telefona_2': _brojTelefona2Controller.text.isEmpty ? null : _brojTelefona2Controller.text.trim(),
      'broj_telefona_oca': _brojTelefonaOcaController.text.isEmpty ? null : _brojTelefonaOcaController.text.trim(),
      'broj_telefona_majke':
          _brojTelefonaMajkeController.text.isEmpty ? null : _brojTelefonaMajkeController.text.trim(),
      'status': (widget.existingPutnik?.status == null) ? 'aktivan' : widget.existingPutnik!.status,
      // Datumi
      'datum_pocetka_meseca': pocetak.toIso8601String().split('T')[0],
      'datum_kraja_meseca': kraj.toIso8601String().split('T')[0],
      // Eksplicitno postavi adrese (uključujući null za brisanje)
      'adresa_bela_crkva_id': _adresaBelaCrkvaId,
      'adresa_vrsac_id': _adresaVrsacId,
      // Cena po danu (custom ili null za default)
      'cena_po_danu': _cenaPoDanuController.text.isEmpty ? null : double.tryParse(_cenaPoDanuController.text),
      // Email
      'email': _emailController.text.isEmpty ? null : _emailController.text.trim(),
      // Polja za račun
      'treba_racun': _trebaRacun,
      'firma_naziv': _firmaNazivController.text.isEmpty ? null : _firmaNazivController.text.trim(),
      'firma_pib': _firmaPibController.text.isEmpty ? null : _firmaPibController.text.trim(),
      'firma_mb': _firmaMbController.text.isEmpty ? null : _firmaMbController.text.trim(),
      'firma_ziro': _firmaZiroController.text.isEmpty ? null : _firmaZiroController.text.trim(),
      'firma_adresa': _firmaAdresaController.text.isEmpty ? null : _firmaAdresaController.text.trim(),
    };
  }

  /// Helper method to show contact picker dialog
  void _showContactPickerDialog(BuildContext context, List<Contact> contacts, TextEditingController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContactPickerSheet(
        contacts: contacts,
        onContactSelected: (phoneNumber) {
          controller.text = phoneNumber;
        },
      ),
    );
  }

  /// Helper method to show permission settings dialog
  void _showPermissionSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Dozvola za kontakte'),
          content: const Text('Dozvola za pristup kontaktima je trajno odbijena. '
              'Da biste mogli da birate kontakte, omogućite dozvolu u podešavanjima aplikacije.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Otkaži'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Otvori podešavanja'),
            ),
          ],
        );
      },
    );
  }
}

class _ContactPickerSheet extends StatefulWidget {
  final List<Contact> contacts;
  final Function(String) onContactSelected;

  const _ContactPickerSheet({
    required this.contacts,
    required this.onContactSelected,
  });

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  late List<Contact> _filteredContacts;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredContacts = widget.contacts;
  }

  void _filterContacts(String query) {
    setState(() {
      _filteredContacts =
          widget.contacts.where((contact) => contact.displayName.toLowerCase().contains(query.toLowerCase())).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // 🛑 Handle for dragging
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 🔎 Search Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Izaberi kontakt',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // 🔦 Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: _filterContacts,
              decoration: InputDecoration(
                hintText: 'Pretraži kontakte...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _filterContacts('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 👥 Contacts List
          Expanded(
            child: _filteredContacts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'Nema pronađenih kontakata',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    itemCount: _filteredContacts.length,
                    itemBuilder: (context, index) {
                      final contact = _filteredContacts[index];
                      final name = contact.displayName;
                      final initials = name.isNotEmpty
                          ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join('').toUpperCase()
                          : '?';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            if (contact.phones.isNotEmpty) {
                              String phoneNumber = contact.phones.first.number;
                              phoneNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
                              widget.onContactSelected(phoneNumber);
                            }
                            Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                // Avatar with modern styling
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isDark
                                          ? [Colors.blue.shade700, Colors.blue.shade900]
                                          : [Colors.blue.shade100, Colors.blue.shade200],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.blue.shade800,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Name and number
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      if (contact.phones.isNotEmpty)
                                        Text(
                                          contact.phones.first.number,
                                          style: TextStyle(
                                            color: isDark ? Colors.white54 : Colors.black45,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Selection indicator
                                Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: Colors.grey.withOpacity(0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
