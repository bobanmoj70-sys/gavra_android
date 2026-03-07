/// Model za zahteve za PIN pristup (v2_pin_zahtevi tabela)
class V2PinZahtev {
  /// Mogući statusi zahteva.
  static const String statusCeka = 'ceka';
  static const String statusOdobren = 'odobren';
  static const String statusOdbijen = 'odbijen';
  static const String statusDirektnaIzmena = 'direktna_izmena';

  final String id;
  final String putnikId;
  final String putnikTabela;
  final String? email;
  final String? telefon;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2PinZahtev({
    required this.id,
    required this.putnikId,
    required this.putnikTabela,
    this.email,
    this.telefon,
    this.status = statusCeka,
    this.createdAt,
    this.updatedAt,
  });

  factory V2PinZahtev.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final putnikId = json['putnik_id'] as String?;
    final putnikTabela = json['putnik_tabela'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2PinZahtev.fromJson: id je null/prazan');
    if (putnikId == null || putnikId.isEmpty) {
      throw ArgumentError('V2PinZahtev.fromJson: putnik_id je null/prazan');
    }
    if (putnikTabela == null || putnikTabela.isEmpty) {
      throw ArgumentError('V2PinZahtev.fromJson: putnik_tabela je null/prazna');
    }
    return V2PinZahtev(
      id: id,
      putnikId: putnikId,
      putnikTabela: putnikTabela,
      email: json['email'] as String?,
      telefon: json['telefon'] as String?,
      status: json['status'] as String? ?? statusCeka,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)?.toLocal()
          : null,
    );
  }

  /// Samo polja koja se šalju pri insertu — id i timestamps generiše baza.
  Map<String, dynamic> toJson() {
    return {
      'putnik_id': putnikId,
      'putnik_tabela': putnikTabela,
      if (email != null) 'email': email,
      if (telefon != null) 'telefon': telefon,
      'status': status,
    };
  }

  V2PinZahtev copyWith({
    String? id,
    String? putnikId,
    String? putnikTabela,
    String? email,
    String? telefon,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V2PinZahtev(
      id: id ?? this.id,
      putnikId: putnikId ?? this.putnikId,
      putnikTabela: putnikTabela ?? this.putnikTabela,
      email: email ?? this.email,
      telefon: telefon ?? this.telefon,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2PinZahtev && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
