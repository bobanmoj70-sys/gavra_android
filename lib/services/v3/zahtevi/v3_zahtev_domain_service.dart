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
      'zeljeno_vreme': vreme,
      'dodeljeno_vreme': vreme,
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
      'zeljeno_vreme': novoVreme,
      'dodeljeno_vreme': null,
      'scheduled_at': null,
      'alt_vreme_pre': null,
      'alt_vreme_posle': null,
      'alt_napomena': null,
      'aktivno': true,
      if (createdAtIso != null) 'created_at': createdAtIso,
      if (updatedBy != null) 'updated_by': updatedBy,
    };
    if (koristiSekundarnu != null) {
      updateData['koristi_sekundarnu'] = koristiSekundarnu;
    }

    await _repository.updateRaw(id, updateData);
  }

  Future<void> offerAlternative({
    required String id,
    String? vremePre,
    String? vremePosle,
    String? napomena,
    String? updatedBy,
  }) async {
    await _repository.updateRaw(id, {
      'status': V3ZahtevStatus.alternativa.name,
      'alt_vreme_pre': vremePre,
      'alt_vreme_posle': vremePosle,
      'alt_napomena': napomena,
      if (updatedBy != null) 'updated_by': updatedBy,
    });
  }
}
