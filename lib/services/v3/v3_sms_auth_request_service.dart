import '../../globals.dart';

class V3SmsAuthRequestService {
  V3SmsAuthRequestService._();

  static Future<void> notifyTargetForSmsAuthRequest({
    required String phone,
    required String otp,
    required String targetV3AuthId,
  }) async {
    final safePhone = phone.trim();
    final safeOtp = otp.trim();
    final targetId = targetV3AuthId.trim();
    if (safePhone.isEmpty || safeOtp.isEmpty || targetId.isEmpty) return;

    try {
      final requesterRow = await supabase
          .from('v3_auth')
          .select('ime,telefon,telefon_2')
          .or('telefon.eq.$safePhone,telefon_2.eq.$safePhone')
          .maybeSingle();

      final requesterName = (requesterRow?['ime']?.toString().trim().isNotEmpty ?? false)
          ? requesterRow!['ime'].toString().trim()
          : 'Nepoznat korisnik';

      final targetRows = await supabase
          .from('v3_auth')
          .select('id,push_token,push_provider,push_token_2,push_provider_2')
          .eq('id', targetId)
          .limit(1);

      final tokens = <Map<String, String>>[];
      final seen = <String>{};

      for (final dynamic raw in targetRows) {
        if (raw is! Map) continue;

        final token1 = (raw['push_token'] ?? '').toString().trim();
        final provider1 = (raw['push_provider'] ?? 'hms').toString().trim().toLowerCase();
        if (token1.isNotEmpty && seen.add(token1)) {
          tokens.add({'token': token1, 'provider': provider1 == 'fcm' ? 'fcm' : 'hms'});
        }

        final token2 = (raw['push_token_2'] ?? '').toString().trim();
        final provider2 = (raw['push_provider_2'] ?? 'hms').toString().trim().toLowerCase();
        if (token2.isNotEmpty && seen.add(token2)) {
          tokens.add({'token': token2, 'provider': provider2 == 'fcm' ? 'fcm' : 'hms'});
        }
      }

      if (tokens.isEmpty) return;

      await supabase.functions.invoke(
        'send-push-notification',
        body: {
          'tokens': tokens,
          'title': 'Novi zahtev za šifru',
          'body': '$requesterName traži šifru za broj $safePhone',
          'data': {
            'type': 'sms_auth_request',
            'phone': safePhone,
            'otp': safeOtp,
            'requester_name': requesterName,
            'payload': 'sms_auth_request|$safePhone|$safeOtp|$requesterName',
          },
          'data_only': false,
        },
      );
    } catch (_) {
      return;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchPendingSmsRequests({int limit = 20}) async {
    final rows = await supabase
        .from('v3_auth')
        .select('id,ime,telefon,telefon_2,sifra,updated_at,tip')
        .not('sifra', 'is', null)
        .order('updated_at', ascending: false)
        .limit(limit);

    return rows.whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList(growable: false);
  }
}
