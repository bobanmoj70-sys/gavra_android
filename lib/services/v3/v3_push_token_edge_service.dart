import 'package:firebase_auth/firebase_auth.dart';

import '../../globals.dart';

class V3PushTokenEdgeService {
  V3PushTokenEdgeService._();

  static Future<void> syncPushToken({
    required String pushToken,
    required String provider,
    required String slot,
    String? expectedTip,
    String? expectedId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Firebase korisnik nije ulogovan.');
    }

    final firebaseIdToken = await user.getIdToken();
    if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
      throw Exception('Firebase ID token je prazan.');
    }

    final response = await supabase.functions.invoke(
      'sync-push-token',
      body: {
        'firebase_id_token': firebaseIdToken,
        'push_token': pushToken,
        'push_provider': provider,
        'slot': slot,
        if (expectedTip != null && expectedTip.isNotEmpty) 'expected_tip': expectedTip,
        if (expectedId != null && expectedId.isNotEmpty) 'expected_id': expectedId,
      },
    );

    final status = response.status;
    final data = response.data;
    final isOk = data is Map && data['ok'] == true;

    if (status < 200 || status >= 300 || !isOk) {
      throw Exception('Edge sync-push-token failed (status=$status, data=$data)');
    }
  }
}
