class V3PutnikProfilMessages {
  V3PutnikProfilMessages._();

  static const String invalidTermTime = '⚠️ Neispravno vreme termina. Pokušajte ponovo.';
  static const String requestReceived =
      '✅ Vaš zahtev je uspešno primljen i biće obrađen u najkraćem roku. Bićete obavešteni o statusu putem aplikacije.';
  static const String requestPendingDispatcher = 'Vaš zahtev je u obradi kod dispečera.';
  static const String alreadyPickedUp = '🚗 Već ste pokupljeni — nije moguće otkazati.';
  static const String logoutSuccess = '✅ Uspešno odjavljeni';
  static const String themeChanged = '🎨 Tema promenjena';

  static String tripCanceled(String dan, String grad) => '✅ Polazak otkazan: $dan $grad';

  static String nonWorkingDay(String datumIso, String reason) => '⛔ Neradan dan ($datumIso). Razlog: $reason';

  static String dnevniDateWindowLocked(String allowedLabel) =>
      'ℹ️ Zbog ograničenog broja mesta, za vaš tip putnika trenutno je moguće zakazivanje samo za $allowedLabel. Zakazivanje za sutra se otvara od 16:00. Hvala na razumevanju.';

  static String schedulingLocked(String vreme, String unlockStr) =>
      '🔒 Zakazivanje za $vreme je zatvoreno.\nNova zakazivanja za sledeću sedmicu otvaraju se u subotu od 03:00 ($unlockStr).';
}
