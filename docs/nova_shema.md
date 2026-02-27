# Nova shema — nacrt

---

## radnici
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| ime | text | obavezno |
| status | text | aktivan / neaktivan / godisnji / bolovanje |
| telefon | text | |
| telefon_2 | text | |
| adresa_bc_id | uuid → adrese | default adresa u BC |
| adresa_vs_id | uuid → adrese | default adresa u VS |
| pin | text | za login |
| email | text | |
| cena_po_danu | numeric | ako ima custom cenu |
| broj_mesta | int default 1 | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## ucenici
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| ime | text | obavezno |
| status | text | aktivan / neaktivan |
| telefon | text | |
| telefon_oca | text | |
| telefon_majke | text | |
| adresa_bc_id | uuid → adrese | default adresa u BC |
| adresa_vs_id | uuid → adrese | default adresa u VS |
| pin | text | |
| email | text | |
| cena_po_danu | numeric | |
| broj_mesta | int default 1 | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## dnevni
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| ime | text | obavezno |
| status | text | aktivan / neaktivan |
| telefon | text | |
| telefon_2 | text | |
| adresa_bc_id | uuid → adrese | default adresa u BC |
| adresa_vs_id | uuid → adrese | default adresa u VS |
| cena | numeric | fiksna cena po vožnji |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## posiljke
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| ime | text | naziv / opis pošiljke |
| status | text | aktivan / neaktivan |
| telefon | text | kontakt |
| adresa_bc_id | uuid → adrese | default adresa u BC |
| adresa_vs_id | uuid → adrese | default adresa u VS |
| cena | numeric | cena po dostavi |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## polasci (bila: seat_requests)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| putnik_id | uuid | FK — koji putnik |
| putnik_tabela | text | radnici / ucenici / dnevni / posiljke |
| dan | text | pon / uto / sre / cet / pet |
| grad | text | BC / VS |
| zeljeno_vreme | time | |
| dodeljeno_vreme | time | |
| status | text | pending / confirmed / pokupljen / otkazano / bez_polaska |
| broj_mesta | int default 1 | |
| adresa_id | uuid → adrese | kopija default adrese, može se promijeniti samo za taj dan+grad+vreme |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## voznje_log (arhiva — samo INSERT, nikad UPDATE)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| putnik_id | uuid | FK (može biti NULL ako putnik obrisan) |
| putnik_ime | text | kopija imena u trenutku događaja |
| putnik_tabela | text | radnici / ucenici / dnevni / posiljke |
| datum | date | |
| dan | text | pon / uto / sre / cet / pet |
| grad | text | BC / VS |
| vreme | time | |
| tip | text | voznja / uplata / otkazivanje / greska |
| iznos | numeric | naplaćeno (ako je uplata) |
| vozac_id | uuid → vozaci | |
| vozac_ime | text | kopija imena vozača |
| detalji | text | slobodan tekst za opis |
| created_at | timestamptz | |

---

## vozac_raspored
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| vozac_id | uuid → vozaci | |
| dan | text | pon / uto / sre / cet / pet |
| grad | text | BC / VS |
| vreme | time | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## vozac_putnik
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| vozac_id | uuid → vozaci | |
| putnik_id | uuid | |
| putnik_tabela | text | radnici / ucenici / dnevni / posiljke |
| dan | text | pon / uto / sre / cet / pet |
| grad | text | BC / VS |
| vreme | time | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## kapacitet_polazaka
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| grad | text | BC / VS |
| vreme | time | |
| max_mesta | int | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

---

## push_tokens
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| token | text | UNIQUE |
| provider | text | fcm / huawei |
| vozac_id | uuid → vozaci | nullable — ako je vozač |
| putnik_id | uuid | nullable — ako je putnik |
| putnik_tabela | text | radnici / ucenici / dnevni / posiljke — nullable |
| updated_at | timestamptz | |

---

## vozaci
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| ime | text | obavezno |
| telefon | text | |
| email | text | |
| sifra | text | za login |
| boja | text | hex boja za UI |

---

## vozila
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| registarski_broj | text | |
| marka | text | |
| model | text | |
| godina_proizvodnje | int | |
| broj_sasije | text | |
| kilometraza | numeric | |
| registracija_vazi_do | date | |
| mali_servis_datum | date | |
| mali_servis_km | numeric | |
| veliki_servis_datum | date | |
| veliki_servis_km | numeric | |
| alternator_datum | date | |
| alternator_km | numeric | |
| akumulator_datum | date | |
| akumulator_km | numeric | |
| gume_datum | date | |
| gume_opis | text | |
| gume_prednje_datum | date | |
| gume_prednje_opis | text | |
| gume_prednje_km | numeric | |
| gume_zadnje_datum | date | |
| gume_zadnje_opis | text | |
| gume_zadnje_km | numeric | |
| plocice_datum | date | |
| plocice_km | numeric | |
| plocice_prednje_datum | date | |
| plocice_prednje_km | numeric | |
| plocice_zadnje_datum | date | |
| plocice_zadnje_km | numeric | |
| trap_datum | date | |
| trap_km | numeric | |
| radio | text | |
| napomena | text | |

---

## vozila_servis (log popravki — samo INSERT)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| vozilo_id | uuid → vozila | |
| tip | text | vrsta popravke/servisa |
| datum | date | |
| km | int | |
| opis | text | |
| cena | numeric | |
| pozicija | text | |
| created_at | timestamptz | |

---

## adrese
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| naziv | text | obavezno |
| grad | text | BC / VS |
| gps_lat | numeric | |
| gps_lng | numeric | |

---

## pumpa_punjenja (samo INSERT)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| datum | date | |
| litri | numeric | |
| cena_po_litru | numeric | |
| ukupno_cena | numeric | |
| napomena | text | |
| created_at | timestamptz | |

---

## pumpa_tocenja (samo INSERT)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| datum | date | |
| vozilo_id | uuid → vozila | |
| litri | numeric | |
| km_vozila | int | |
| napomena | text | |
| created_at | timestamptz | |

---

## pumpa_config (1 red)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| kapacitet_litri | numeric | |
| alarm_nivo | numeric | |
| pocetno_stanje | numeric | |
| updated_at | timestamptz | |

---

## finansije_troskovi
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| naziv | text | obavezno |
| tip | text | |
| iznos | numeric | |
| mesecno | boolean | |
| aktivan | boolean | |
| vozac_id | uuid → vozaci | nullable |
| mesec | int | |
| godina | int | |
| created_at | timestamptz | |

---

## app_settings (1 red)
| kolona | tip | |
|---|---|---|
| id | text | PK (npr. "global") |
| min_version | text | |
| latest_version | text | |
| store_url_android | text | |
| store_url_huawei | text | |
| store_url_ios | text | |
| nav_bar_type | text | |
| updated_at | timestamptz | |
| updated_by | text | |

---

## pin_zahtevi (samo INSERT)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| putnik_id | uuid | |
| putnik_tabela | text | radnici / ucenici / dnevni / posiljke |
| email | text | |
| telefon | text | |
| status | text | |
| created_at | timestamptz | |

---

## vozac_lokacije (live — UPDATE po vozaču)
| kolona | tip | |
|---|---|---|
| id | uuid | PK auto |
| vozac_id | uuid → vozaci | |
| lat | numeric | |
| lng | numeric | |
| grad | text | BC / VS |
| vreme_polaska | text | |
| smer | text | |
| putnici_eta | jsonb | |
| aktivan | boolean | |
| updated_at | timestamptz | |

---

## Napomena: status putnika
- `aktivan` — vozi normalno
- `neaktivan` — privremeno ne vozi
- `godisnji` / `bolovanje` — samo za radnike
- **nema `obrisan`** — brisanje je stvarno brisanje (`DELETE`), log čuva istoriju kroz `putnik_ime`
