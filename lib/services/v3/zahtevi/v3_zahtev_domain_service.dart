import 'v3_zahtev_repository.dart';
import 'v3_zahtev_types.dart';

class V3ZahtevDomainService {
  final V3ZahtevRepository _repository;

  V3ZahtevDomainService(this._repository);

  Future<Map<String, dynamic>> setStatus({
    required String id,
    required V3ZahtevStatus status,
    String? updatedBy,
  }) {
    return _repository.updateRaw(id, {
      'status': status.name,
      if (updatedBy != null) 'updated_by': updatedBy,
    });
  }

  Future<Map<String, dynamic>> assignTime({
    required String id,
    required String vreme,
    String? status,
    String? updatedBy,
  }) {
    return _repository.updateRaw(id, {
      'trazeni_polazak_at': vreme,
      'polazak_at': vreme,
      if (status != null) 'status': status,
      if (updatedBy != null) 'updated_by': updatedBy,
    });
  }

  Future<void> resetToObrada({
    required String id,
    required String novoVreme,
    bool? koristiSekundarnu,
    String? updatedBy,
    String? createdAtIso,
  }) async {
    final updateData = <String, dynamic>{
      'status': V3ZahtevStatus.obrada.name,
      'trazeni_polazak_at': novoVreme,
      'polazak_at': null,
      'scheduled_at': null,
      'alternativa_pre_at': null,
      'alternativa_posle_at': null,
      if (createdAtIso != null) 'created_at': createdAtIso,
      if (updatedBy != null) 'updated_by': updatedBy,
    };
    if (koristiSekundarnu != null) {
      updateData['koristi_sekundarnu'] = koristiSekundarnu;
    }

    await _repository.updateRaw(id, updateData);
  }
}
