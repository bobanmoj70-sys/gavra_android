part of 'app_translations.dart';

const Map<String, Map<String, Map<String, String>>> _widgetsAndUtils = {
  'dialogHelper': {
    'yes': {'sr': 'Da', 'en': 'Yes', 'ru': 'Да', 'de': 'Ja', 'zh': '是'},
    'no': {'sr': 'Ne', 'en': 'No', 'ru': 'Нет', 'de': 'Nein', 'zh': '否'},
    'ok': {'sr': 'U redu', 'en': 'OK', 'ru': 'ОК', 'de': 'OK', 'zh': '确定'},
    'loading': {
      'sr': 'Učitavanje...',
      'en': 'Loading...',
      'ru': 'Загрузка...',
      'de': 'Wird geladen...',
      'zh': '加载中...',
    },
    'confirm': {
      'sr': 'Potvrdi',
      'en': 'Confirm',
      'ru': 'Подтвердить',
      'de': 'Bestätigen',
      'zh': '确认',
    },
    'cancel': {
      'sr': 'Otkaži',
      'en': 'Cancel',
      'ru': 'Отмена',
      'de': 'Abbrechen',
      'zh': '取消'
    },
    'working': {
      'sr': 'Radi...',
      'en': 'Working...',
      'ru': 'Выполняется...',
      'de': 'Wird ausgeführt...',
      'zh': '处理中...'
    },
  },
  'uiUtils': {
    'saved': {
      'sr': '✅ Sačuvano',
      'en': '✅ Saved',
      'ru': '✅ Сохранено',
      'de': '✅ Gespeichert',
      'zh': '✅ 已保存'
    },
    'saveError': {
      'sr': '❌ Greška pri čuvanju',
      'en': '❌ Error while saving',
      'ru': '❌ Ошибка при сохранении',
      'de': '❌ Fehler beim Speichern',
      'zh': '❌ 保存时出错',
    },
    'errorDuring': {
      'sr': '❌ Greška pri %ACTION%: %ERROR%',
      'en': '❌ Error during %ACTION%: %ERROR%',
      'ru': '❌ Ошибка при %ACTION%: %ERROR%',
      'de': '❌ Fehler bei %ACTION%: %ERROR%',
      'zh': '❌ %ACTION% 时出错：%ERROR%',
    },
  },
  'putnikCard': {
    'notLoggedIn': {
      'sr': 'Niste logovani u V3 sistem',
      'en': 'You are not logged in to the V3 system',
      'ru': 'Вы не вошли в систему V3',
      'de': 'Sie sind nicht im V3-System angemeldet',
      'zh': '您尚未登录V3系统',
    },
    'rideRecorded': {
      'sr': 'Vožnja evidentirana',
      'en': 'Ride recorded',
      'ru': 'Поездка зафиксирована',
      'de': 'Fahrt erfasst',
      'zh': '行程已记录',
    },
    'pickupRecordError': {
      'sr': 'Greška pri evidenciji vožnje',
      'en': 'Error while recording ride',
      'ru': 'Ошибка при фиксации поездки',
      'de': 'Fehler beim Erfassen der Fahrt',
      'zh': '记录行程时出错',
    },
    'contactPassenger': {
      'sr': 'Kontaktiraj',
      'en': 'Contact',
      'ru': 'Связаться',
      'de': 'Kontaktieren',
      'zh': '联系',
    },
    'hereWeGoInstallTitle': {
      'sr': 'Da biste koristili ovu funkciju, molimo instalirajte HERE WeGo.',
      'en': 'To use this feature, please install HERE WeGo.',
      'ru': 'Чтобы использовать эту функцию, установите HERE WeGo.',
      'de': 'Um diese Funktion zu nutzen, installieren Sie bitte HERE WeGo.',
      'zh': '要使用此功能，请安装 HERE WeGo。',
    },
    'hereWeGoInstallAction': {
      'sr': 'INSTALIRAJ',
      'en': 'INSTALL',
      'ru': 'УСТАНОВИТЬ',
      'de': 'INSTALLIEREN',
      'zh': '安装'
    },
    'noGpsCoordinatesForAddress': {
      'sr': 'Nema GPS koordinata za ovu adresu',
      'en': 'No GPS coordinates for this address',
      'ru': 'Нет GPS-координат для этого адреса',
      'de': 'Keine GPS-Koordinaten für diese Adresse',
      'zh': '此地址没有 GPS 坐标',
    },
    'cancel': {
      'sr': 'Otkaži',
      'en': 'Cancel',
      'ru': 'Отмена',
      'de': 'Abbrechen',
      'zh': '取消',
    },
    'call': {
      'sr': 'Pozovi',
      'en': 'Call',
      'ru': 'Позвонить',
      'de': 'Anrufen',
      'zh': '拨打',
    },
    'sms': {
      'sr': 'SMS',
      'en': 'SMS',
      'ru': 'SMS',
      'de': 'SMS',
      'zh': '短信',
    },
    'driverExcludedFromPassengerBilling': {
      'sr': 'Vozač ne ulazi u putničku naplatu.',
      'en': 'Driver is excluded from passenger billing.',
      'ru': 'Водитель не участвует в пассажирской оплате.',
      'de': 'Fahrer ist von der Fahrgastabrechnung ausgeschlossen.',
      'zh': '司机不参与乘客计费。',
    },
    'chargedAmountForPassenger': {
      'sr': '✅ Naplaćeno %AMOUNT% RSD za %NAME%',
      'en': '✅ Charged %AMOUNT% RSD for %NAME%',
      'ru': '✅ Списано %AMOUNT% RSD за %NAME%',
      'de': '✅ %AMOUNT% RSD für %NAME% berechnet',
      'zh': '✅ 已向%NAME%收取 %AMOUNT% RSD',
    },
    'paymentDiffInfo': {
      'sr': 'Obračun %EXPECTED% RSD, uneto %ENTERED% RSD, razlika %DIFF% RSD',
      'en':
          'Calculation %EXPECTED% RSD, entered %ENTERED% RSD, difference %DIFF% RSD',
      'ru': 'Расчёт %EXPECTED% RSD, внесено %ENTERED% RSD, разница %DIFF% RSD',
      'de':
          'Abrechnung %EXPECTED% RSD, eingegeben %ENTERED% RSD, Differenz %DIFF% RSD',
      'zh': '结算 %EXPECTED% RSD，输入 %ENTERED% RSD，差额 %DIFF% RSD',
    },
    'paymentError': {
      'sr': 'Greška pri plaćanju',
      'en': 'Payment error',
      'ru': 'Ошибка при оплате',
      'de': 'Fehler bei der Zahlung',
      'zh': '支付出错',
    },
    'passengerAlreadyPickedUp': {
      'sr': 'Putnik je već pokupljen, ne može se otkazati.',
      'en': 'Passenger is already picked up and cannot be canceled.',
      'ru': 'Пассажир уже забран, отмена невозможна.',
      'de': 'Fahrgast wurde bereits abgeholt und kann nicht storniert werden.',
      'zh': '乘客已接载，无法取消。',
    },
    'cancelPassengerTitle': {
      'sr': 'Otkazivanje putnika',
      'en': 'Cancel passenger',
      'ru': 'Отмена пассажира',
      'de': 'Fahrgast stornieren',
      'zh': '取消乘客',
    },
    'confirmCancelPassenger': {
      'sr': 'Da li ste sigurni da želite da otkaže %NAME%?',
      'en': 'Are you sure you want to cancel %NAME%?',
      'ru': 'Вы уверены, что хотите отменить %NAME%?',
      'de': 'Möchten Sie %NAME% wirklich stornieren?',
      'zh': '确定要取消 %NAME% 吗？',
    },
    'yes': {'sr': 'Da', 'en': 'Yes', 'ru': 'Да', 'de': 'Ja', 'zh': '是'},
    'no': {'sr': 'Ne', 'en': 'No', 'ru': 'Нет', 'de': 'Nein', 'zh': '否'},
    'canceledPassenger': {
      'sr': 'Otkazano: %NAME%',
      'en': 'Canceled: %NAME%',
      'ru': 'Отменено: %NAME%',
      'de': 'Storniert: %NAME%',
      'zh': '已取消：%NAME%',
    },
    'genericError': {
      'sr': 'Greška',
      'en': 'Error',
      'ru': 'Ошибка',
      'de': 'Fehler',
      'zh': '错误',
    },
    'ridesPlural': {
      'sr': 'Vožnje',
      'en': 'Rides',
      'ru': 'Поездки',
      'de': 'Fahrten',
      'zh': '行程'
    },
    'rideSingular': {
      'sr': 'Vožnja',
      'en': 'Ride',
      'ru': 'Поездка',
      'de': 'Fahrt',
      'zh': '行程'
    },
    'total': {
      'sr': 'Ukupno',
      'en': 'Total',
      'ru': 'Всего',
      'de': 'Gesamt',
      'zh': '总计'
    },
    'last': {
      'sr': 'Poslednje',
      'en': 'Last',
      'ru': 'Последнее',
      'de': 'Letzte',
      'zh': '最近'
    },
    'canceled': {
      'sr': 'Otkazano',
      'en': 'Canceled',
      'ru': 'Отменено',
      'de': 'Storniert',
      'zh': '已取消'
    },
  },
  'updateBannerUpdateBannerTranslations': {
    'maintenanceWorkInProgress': {
      'sr': '⛔ Radovi u toku — ne diraj kablove 😄',
      'en': '⛔ Maintenance in progress — please do not touch cables 😄',
      'ru': '⛔ Идут работы — пожалуйста, не трогайте кабели 😄',
      'de': '⛔ Wartungsarbeiten laufen — bitte keine Kabel berühren 😄',
      'zh': '⛔ 维护进行中——请勿触碰电缆 😄',
    },
    'updateRequired': {
      'sr': 'Potrebno ažuriranje',
      'en': 'Update required',
      'ru': 'Требуется обновление',
      'de': 'Update erforderlich',
      'zh': '需要更新',
    },
    'versionLabel': {
      'sr': 'verzija',
      'en': 'version',
      'ru': 'версия',
      'de': 'Version',
      'zh': '版本',
    },
    'unsupportedVersionMessage': {
      'sr':
          'Ova verzija aplikacije više nije podržana. Ažurirajte aplikaciju da biste nastavili rad.',
      'en':
          'This app version is no longer supported. Please update the app to continue.',
      'ru':
          'Эта версия приложения больше не поддерживается. Обновите приложение, чтобы продолжить работу.',
      'de':
          'Diese App-Version wird nicht mehr unterstützt. Bitte aktualisieren Sie die App, um fortzufahren.',
      'zh': '此应用版本已不再受支持。请更新应用后继续使用。',
    },
    'updateApp': {
      'sr': 'Ažuriraj aplikaciju',
      'en': 'Update app',
      'ru': 'Обновить приложение',
      'de': 'App aktualisieren',
      'zh': '更新应用',
    },
  },
  'vremeDolaskaWidget': {
    'procenjenoVreme': {
      'sr': 'Procenjeno vreme dolaska',
      'en': 'Estimated arrival time',
      'ru': 'Ориентировочное время прибытия',
      'de': 'Geschätzte Ankunftszeit',
      'zh': '预计到达时间',
    },
    'zaMin': {'sr': 'za', 'en': 'in', 'ru': 'через', 'de': 'in', 'zh': '还有'},
    'min': {'sr': 'min', 'en': 'min', 'ru': 'мин', 'de': 'Min', 'zh': '分钟'},
    'sledecaVoznja': {
      'sr': 'Sledeća vožnja',
      'en': 'Next ride',
      'ru': 'Следующая поездка',
      'de': 'Nächste Fahrt',
      'zh': '下一趟行程',
    },
    'nemaZakazaneVoznje': {
      'sr': 'Nema zakazane vožnje',
      'en': 'No scheduled ride',
      'ru': 'Нет запланированной поездки',
      'de': 'Keine geplante Fahrt',
      'zh': '没有安排的行程',
    },
    'cekaNa': {
      'sr': 'Čeka na',
      'en': 'Waiting at',
      'ru': 'Ожидает у',
      'de': 'Wartet bei',
      'zh': '等待于'
    },
    'vozac': {
      'sr': 'Vozač',
      'en': 'Driver',
      'ru': 'Водитель',
      'de': 'Fahrer',
      'zh': '司机'
    },
    'u': {'sr': 'u', 'en': 'at', 'ru': 'в', 'de': 'um', 'zh': '于'},
    'noGpsForAddress': {
      'sr': 'Nema GPS koordinata za ovu adresu',
      'en': 'No GPS coordinates for this address',
      'ru': 'Для этого адреса нет GPS-координат',
      'de': 'Keine GPS-Koordinaten für diese Adresse',
      'zh': '此地址没有GPS坐标',
    },
    'cannotOpenGoogleMaps': {
      'sr': 'Ne mogu da otvorim Google Maps',
      'en': 'Cannot open Google Maps',
      'ru': 'Не удается открыть Google Maps',
      'de': 'Google Maps kann nicht geöffnet werden',
      'zh': '无法打开Google地图',
    },
  },
};
