import '../services/v3_locale_manager.dart';

class V3PutnikProfilMessages {
  V3PutnikProfilMessages._();

  static String get _lang => V3LocaleManager().currentLocale.languageCode;

  static String get invalidTermTime => switch (_lang) {
        'en' => '⚠️ Invalid appointment time. Please try again.',
        'ru' => '⚠️ Неверное время записи. Попробуйте снова.',
        'de' => '⚠️ Ungültige Terminzeit. Bitte versuchen Sie es erneut.',
        _ => '⚠️ Neispravno vreme termina. Pokušajte ponovo.',
      };

  static String get requestReceived => switch (_lang) {
        'en' =>
          '✅ Your request has been received and will be processed shortly. You will be notified of the status via the app.',
        'ru' =>
          '✅ Ваш запрос принят и будет обработан в ближайшее время. Вы получите уведомление о статусе через приложение.',
        'de' =>
          '✅ Ihre Anfrage wurde empfangen und wird in Kürze bearbeitet. Sie werden über den Status in der App benachrichtigt.',
        _ =>
          '✅ Vaš zahtev je uspešno primljen i biće obrađen u najkraćem roku. Bićete obavešteni o statusu putem aplikacije.',
      };

  static String get requestPendingDispatcher => switch (_lang) {
        'en' => 'Your request is being processed by the dispatcher.',
        'ru' => 'Ваш запрос обрабатывается диспетчером.',
        'de' => 'Ihre Anfrage wird vom Disponenten bearbeitet.',
        _ => 'Vaš zahtev je u obradi kod dispečera.',
      };

  static String get alreadyPickedUp => switch (_lang) {
        'en' => '🚗 The ride has already been recorded — cancellation not possible.',
        'ru' => '🚗 Поездка уже зафиксирована — отмена невозможна.',
        'de' => '🚗 Die Fahrt wurde bereits erfasst — Stornierung nicht möglich.',
        _ => '🚗 Vožnja je već evidentirana — nije moguće otkazati.',
      };

  static String get logoutSuccess => switch (_lang) {
        'en' => '✅ Successfully logged out',
        'ru' => '✅ Вы успешно вышли',
        'de' => '✅ Erfolgreich abgemeldet',
        _ => '✅ Uspešno odjavljeni',
      };

  static String get themeChanged => switch (_lang) {
        'en' => '🎨 Theme changed',
        'ru' => '🎨 Тема изменена',
        'de' => '🎨 Thema geändert',
        _ => '🎨 Tema promenjena',
      };

  static String tripCanceled(String dan, String grad) => switch (_lang) {
        'en' => '✅ Departure canceled: $dan $grad',
        'ru' => '✅ Отправление отменено: $dan $grad',
        'de' => '✅ Abfahrt storniert: $dan $grad',
        _ => '✅ Polazak otkazan: $dan $grad',
      };

  static String nonWorkingDay(String datumIso, String reason) => switch (_lang) {
        'en' => '⛔ Non-working day ($datumIso). Reason: $reason',
        'ru' => '⛔ Нерабочий день ($datumIso). Причина: $reason',
        'de' => '⛔ Arbeitsfreier Tag ($datumIso). Grund: $reason',
        _ => '⛔ Neradan dan ($datumIso). Razlog: $reason',
      };

  static String dnevniDateWindowLocked(String allowedLabel) => switch (_lang) {
        'en' =>
          '📅 Scheduling for daily passengers is only possible for $allowedLabel.\nBefore 16:00 you schedule for the current day, after 16:00 – for the next working day.',
        'ru' =>
          '📅 Планирование для ежедневных пассажиров возможно только на $allowedLabel.\nДо 16:00 планируется на текущий день, после 16:00 — на следующий рабочий день.',
        'de' =>
          '📅 Die Planung für Tagesfahrgäste ist nur für $allowedLabel möglich.\nVor 16:00 Uhr wird für den aktuellen Tag geplant, nach 16:00 Uhr – für den nächsten Arbeitstag.',
        _ =>
          '📅 Zakazivanje za dnevne putnike je moguće samo za $allowedLabel.\nPre 16:00 zakazuje se za tekući dan, posle 16:00 – za sledeći radni dan.',
      };

  static String schedulingLocked(String vreme, String unlockStr) => switch (_lang) {
        'en' =>
          '🔒 Scheduling for $vreme is closed.\nNew scheduling for next week opens on Saturday at 03:00 ($unlockStr).',
        'ru' =>
          '🔒 Планирование на $vreme закрыто.\nНовое планирование на следующую неделю откроется в субботу в 03:00 ($unlockStr).',
        'de' =>
          '🔒 Die Planung für $vreme ist geschlossen.\nDie neue Planung für die nächste Woche öffnet am Samstag um 03:00 Uhr ($unlockStr).',
        _ =>
          '🔒 Zakazivanje za $vreme je zatvoreno.\nNova zakazivanja za sledeću sedmicu otvaraju se u subotu od 03:00 ($unlockStr).',
      };
}
