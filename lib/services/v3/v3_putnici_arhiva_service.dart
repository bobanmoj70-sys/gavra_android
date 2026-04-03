import '../../models/v3_putnik_arhiva.dart';
import 'v3_uplate_arhiva_service.dart';

@Deprecated('Koristi V3UplateArhivaService.')
class V3PutniciArhivaService {
  V3PutniciArhivaService._();

  static List<V3PutnikArhiva> getByPutnik(String putnikId) {
    return V3UplateArhivaService.getByPutnik(putnikId);
  }

  static List<V3PutnikArhiva> getForPeriod({required int mesec, required int godina}) {
    return V3UplateArhivaService.getForPeriod(mesec: mesec, godina: godina);
  }

  static Stream<List<V3PutnikArhiva>> streamByPutnik(String putnikId) {
    return V3UplateArhivaService.streamByPutnik(putnikId);
  }

  static Future<void> addZapis(V3PutnikArhiva zapis) async {
    return V3UplateArhivaService.addZapis(zapis);
  }
}
