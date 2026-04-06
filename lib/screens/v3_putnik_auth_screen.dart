import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import 'v3_putnik_profil_screen.dart';

enum _AuthStep { phone, email, waiting }

class V3PutnikAuthScreen extends StatefulWidget {
  const V3PutnikAuthScreen({super.key});

  @override
  State<V3PutnikAuthScreen> createState() => _V3PutnikAuthScreenState();
}

class _V3PutnikAuthScreenState extends State<V3PutnikAuthScreen> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  _AuthStep _step = _AuthStep.phone;
  bool _isLoading = false;
  String? _normalizedPhone;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(_finalizeLogin());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _checkPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite broj telefona.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final normalized = V3ClosedAuthService.normalizePhone(phone);
      final exists = await V3ClosedAuthService.phoneExists(normalized);
      if (!mounted) return;

      if (!exists) {
        V3AppSnackBar.error(context, 'Broj telefona nije pronađen u sistemu.');
        return;
      }

      setState(() {
        _normalizedPhone = normalized;
        _step = _AuthStep.email;
      });
      V3AppSnackBar.info(context, 'Telefon potvrđen. Unesite email adresu.');
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška pri proveri telefona: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMagicLink() async {
    final phone = _normalizedPhone ?? _phoneController.text.trim();
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite email adresu.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await V3ClosedAuthService.sendMagicLink(rawPhone: phone, email: email);
      if (!mounted) return;

      setState(() => _step = _AuthStep.waiting);
      V3AppSnackBar.success(context, 'Link je poslat. Potvrdite email pa nastavite.');
    } on AuthException catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Auth greška: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška pri slanju linka: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _finalizeLogin() async {
    final phone = _normalizedPhone ?? _phoneController.text.trim();
    if (phone.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        V3AppSnackBar.info(context, 'Još nema potvrđene sesije. Otvorite link iz emaila.');
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final linked = await V3ClosedAuthService.linkCurrentUserToPhone(phone);
      if (!mounted) return;

      if (!linked) {
        await Supabase.instance.client.auth.signOut();
        V3AppSnackBar.error(context, 'Mapiranje telefona i auth naloga nije dozvoljeno.');
        return;
      }

      final normalized = V3ClosedAuthService.normalizePhone(phone);
      final putnik = await V3PutnikService.getByPhoneOrCache(normalized);

      if (!mounted) return;

      if (putnik == null) {
        V3AppSnackBar.error(context, 'Korisnički profil nije pronađen za ovaj telefon.');
        return;
      }

      V3PutnikService.currentPutnik = putnik;
      await V3RolePermissionService.ensurePassengerPermissionsOnLogin();

      if (!mounted) return;
      V3NavigationUtils.pushReplacement(
        context,
        V3PutnikProfilScreen(putnikData: putnik),
      );
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška pri finalizaciji prijave: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.backgroundContainer(
      gradient: Theme.of(context).backgroundGradient,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '🔐 Putnik prijava',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + kToolbarHeight + 24,
            24,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              _buildPhoneStep(),
              const SizedBox(height: 16),
              if (_step != _AuthStep.phone) _buildEmailStep(),
              const SizedBox(height: 24),
              if (_step == _AuthStep.phone)
                V3ButtonUtils.primaryButton(
                  text: 'Proveri telefon',
                  icon: Icons.phone,
                  isLoading: _isLoading,
                  onPressed: _checkPhone,
                ),
              if (_step == _AuthStep.email)
                V3ButtonUtils.primaryButton(
                  text: 'Pošalji magic link',
                  icon: Icons.mark_email_unread,
                  isLoading: _isLoading,
                  onPressed: _sendMagicLink,
                ),
              if (_step == _AuthStep.waiting) ...[
                V3ButtonUtils.primaryButton(
                  text: 'Potvrdio sam link',
                  icon: Icons.verified_user,
                  isLoading: _isLoading,
                  onPressed: _finalizeLogin,
                ),
                const SizedBox(height: 12),
                V3ButtonUtils.cancelButton(
                  text: 'Pošalji ponovo link',
                  icon: Icons.refresh,
                  isLoading: _isLoading,
                  onPressed: _sendMagicLink,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return V3InputUtils.formField(
      controller: _phoneController,
      label: 'Broj telefona',
      icon: Icons.phone,
      hint: '06x xxx xxxx',
      keyboardType: TextInputType.phone,
      validator: (_) => null,
      onSubmitted: (_) {
        if (_step == _AuthStep.phone && !_isLoading) {
          unawaited(_checkPhone());
        }
      },
    );
  }

  Widget _buildEmailStep() {
    return V3InputUtils.emailField(
      controller: _emailController,
      label: 'Email adresa',
      hint: 'ime.prezime@email.com',
      isRequired: true,
    );
  }
}
