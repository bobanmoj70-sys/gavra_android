import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Model za vozače
class V2Vozac {
  V2Vozac({
    String? id,
    required this.ime,
    this.brojTelefona,
    this.email,
    this.boja,
    this.sifra,
  })  : assert(ime.trim().isNotEmpty, 'Ime vozača ne može biti prazno'),
        id = id ?? const Uuid().v4();

  factory V2Vozac.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) throw ArgumentError('V2Vozac.fromMap: id je null ili prazan');
    return V2Vozac(
      id: id,
      ime: map['ime']?.toString() ?? '',
      brojTelefona: map['telefon']?.toString(),
      email: map['email']?.toString(),
      boja: map['boja']?.toString(),
      sifra: map['sifra']?.toString(),
    );
  }
  final String id;
  final String ime;
  final String? brojTelefona;
  final String? email;
  final String? boja;
  final String? sifra;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ime': ime,
      if (brojTelefona != null) 'telefon': brojTelefona,
      if (email != null) 'email': email,
      if (boja != null) 'boja': boja,
      if (sifra != null) 'sifra': sifra,
    };
  }

  /// Vraća boju vozača kao Color objekat
  /// Parsira hex string (npr. '#FF0000') u Color
  Color? get color {
    if (boja == null || boja!.isEmpty) return null;
    try {
      final hex = boja!.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return null;
    }
  }

  /// Validira da li je ime vozača validno (ne sme biti prazno)
  bool get isValidIme {
    return ime.trim().isNotEmpty && ime.trim().length >= 2;
  }

  /// Validira telefon format (srpski broj)
  bool get isValidTelefon {
    if (brojTelefona == null || brojTelefona!.isEmpty) {
      return true; // Optional field
    }

    final telefon = brojTelefona!.replaceAll(RegExp(r'[^\d+]'), '');

    // Srpski mobilni: +381 6x xxx xxxx ili 06x xxx xxxx
    // Srpski fiksni: +381 1x xxx xxxx ili 01x xxx xxxx
    return telefon.startsWith('+3816') ||
        telefon.startsWith('06') ||
        telefon.startsWith('+3811') ||
        telefon.startsWith('01') ||
        telefon.length == 8 ||
        telefon.length == 9; // lokalni brojevi
  }

  /// Validira email format
  bool get isValidEmail {
    if (email == null || email!.isEmpty) return true; // Optional field

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email!);
  }

  /// Kompletna validacija vozača
  bool get isValid {
    return isValidIme && isValidTelefon && isValidEmail;
  }

  /// Kreira kopiju vozača sa promenjenim vrednostima
  V2Vozac copyWith({
    String? ime,
    Object? brojTelefona = _sentinel,
    Object? email = _sentinel,
    Object? boja = _sentinel,
    Object? sifra = _sentinel,
  }) {
    return V2Vozac(
      id: id,
      ime: ime ?? this.ime,
      brojTelefona: brojTelefona == _sentinel ? this.brojTelefona : brojTelefona as String?,
      email: email == _sentinel ? this.email : email as String?,
      boja: boja == _sentinel ? this.boja : boja as String?,
      sifra: sifra == _sentinel ? this.sifra : sifra as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (runtimeType == other.runtimeType && other is V2Vozac && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2Vozac(id: $id, ime: $ime, boja: $boja)';
}

const _sentinel = Object();
