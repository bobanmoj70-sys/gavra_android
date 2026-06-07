import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SchemaColumn {
  column_name: string;
  data_type: string;
  is_nullable: string;
  column_default: string | null;
  check_constraint: string | null;
}

interface SchemaTable {
  table_name: string;
  columns: SchemaColumn[];
  row_count: number;
  sample_data: Record<string, unknown>[];
}

async function getSchema(supabase: SupabaseClient): Promise<SchemaTable[]> {
  const { data, error } = await supabase.rpc("analyze_schema");
  if (error || !data) throw error || new Error("analyze_schema vratio prazan rezultat");

  // data je JSONB, Supabase ga vraća kao objekat
  const raw = Array.isArray(data) ? data : JSON.parse(data as string);

  return raw.map((t: Record<string, unknown>) => {
    const columns = (t.columns as Array<Record<string, unknown>> || []).map((c) => {
      const constraints = t.constraints as Array<Record<string, unknown>> || [];
      const check = constraints.find(
        (con) => (con.constraint_name as string)?.includes(c.column_name as string)
      );
      return {
        column_name: c.column_name as string,
        data_type: c.data_type as string,
        is_nullable: c.is_nullable as string,
        column_default: c.column_default as string | null,
        check_constraint: check?.check_clause as string | null,
      };
    });

    return {
      table_name: t.table_name as string,
      columns,
      row_count: Number(t.row_count || 0),
      sample_data: (t.sample_data as Array<Record<string, unknown>>) || [],
    };
  });
}

function analyzeTable(table: SchemaTable): Array<{
  tip: string;
  entitet: string;
  atribut: string | null;
  zakljucak: string;
  confidence: number;
  nauceno_od: string;
}> {
  const findings: Array<{
    tip: string;
    entitet: string;
    atribut: string | null;
    zakljucak: string;
    confidence: number;
    nauceno_od: string;
  }> = [];

  const name = table.table_name;

  if (name.includes("gorivo")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja evidenciju goriva ili rezervoar. Ima ${table.row_count} redova.`,
      confidence: 0.7,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("auth")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja korisnike/sisteme autentifikacije. Ima ${table.row_count} redova.`,
      confidence: 0.8,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("zahtevi")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja zahteve (npr. za voznju, uslugu). Ima ${table.row_count} redova.`,
      confidence: 0.7,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("operativna")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja operativni plan ili raspored. Ima ${table.row_count} redova.`,
      confidence: 0.6,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("finansije")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja finansijske transakcije. Ima ${table.row_count} redova.`,
      confidence: 0.8,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("vozila")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" predstavlja evidenciju vozila. Ima ${table.row_count} redova.`,
      confidence: 0.9,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("adrese")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" predstavlja adresar lokacija. Ima ${table.row_count} redova.`,
      confidence: 0.9,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("trenutna_dodela")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja trenutnu dodelu putnika vozacima. Ima ${table.row_count} redova.`,
      confidence: 0.7,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("kapacitet")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" verovatno predstavlja kapacitete/raspored mesta. Ima ${table.row_count} redova.`,
      confidence: 0.7,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("app_settings")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" sadrzi globalna podesavanja aplikacije i raspored polazaka. Ima ${table.row_count} redova.`,
      confidence: 0.8,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("eta_results")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" sadrzi rezultate procene vremena dolaska (ETA). Koristi se za prikaz vremena dolaska putnicima. Ima ${table.row_count} redova.`,
      confidence: 0.85,
      nauceno_od: "ime_tabele",
    });
  } else if (name.includes("racuni")) {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" predstavlja izdate racune/fakture. Ima ${table.row_count} redova.`,
      confidence: 0.8,
      nauceno_od: "ime_tabele",
    });
  } else {
    findings.push({
      tip: "tabela",
      entitet: name,
      atribut: null,
      zakljucak: `Tabela "${name}" ima ${table.row_count} redova. Potrebno dalje istrazivanje.`,
      confidence: 0.3,
      nauceno_od: "ime_tabele",
    });
  }

  for (const col of table.columns) {
    const colName = col.column_name;
    const colType = col.data_type;

    if (colName === "id" && colType === "uuid") {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: "Primarni kljuc tipa UUID. Jedinstveni identifikator reda.",
        confidence: 0.95,
        nauceno_od: "schema_tip",
      });
    }

    if (colName === "status") {
      if (col.check_constraint) {
        findings.push({
          tip: "kolona",
          entitet: name,
          atribut: colName,
          zakljucak: `Status sa ogranicenim vrednostima: ${col.check_constraint}. Kontrolise stanje/zivotni ciklus.`,
          confidence: 0.85,
          nauceno_od: "schema_check",
        });
      } else {
        findings.push({
          tip: "kolona",
          entitet: name,
          atribut: colName,
          zakljucak: "Status kolona. Verovatno kontrolise stanje reda.",
          confidence: 0.6,
          nauceno_od: "ime_kolone",
        });
      }
    }

    if (colName === "ime" || colName.includes("naziv")) {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: "Naziv ili ime entiteta. Tekstualni opis.",
        confidence: 0.8,
        nauceno_od: "ime_kolone",
      });
    }

    if (colName === "grad") {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: "Grad/lokacija. Moze biti filter za podatke.",
        confidence: 0.7,
        nauceno_od: "ime_kolone",
      });
    }

    if (colName.includes("gps") || colName.includes("lat") || colName.includes("lng")) {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: "Geografska koordinata. Koriscena za lokaciju/mapu.",
        confidence: 0.9,
        nauceno_od: "ime_kolone",
      });
    }

    if (colName.includes("cena") || colName.includes("iznos") || colName.includes("dug")) {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: `Novcana vrednost. Tip: ${colType}. Moze biti u dinarima.`,
        confidence: 0.75,
        nauceno_od: "ime_kolone",
      });
    }

    if (colName.includes("datum") || colName.includes("vreme") || colName.includes("_at")) {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: `Vremenska oznaka. Tip: ${colType}. Koristi se za sortiranje i filtriranje po vremenu.`,
        confidence: 0.85,
        nauceno_od: "ime_kolone",
      });
    }

    if (colType === "boolean") {
      findings.push({
        tip: "kolona",
        entitet: name,
        atribut: colName,
        zakljucak: `Flag (da/ne). Aktivira/iskljucuje neku funkcionalnost.`,
        confidence: 0.7,
        nauceno_od: "schema_tip",
      });
    }

    if (colName.endsWith("_id") && colName !== "id") {
      const targetTable = colName.replace("_id", "").replace("v3_", "v3_");
      findings.push({
        tip: "veza",
        entitet: name,
        atribut: colName,
        zakljucak: `Foreign key — verovatno pokazuje na tabelu "${targetTable}" ili slicnu.`,
        confidence: 0.6,
        nauceno_od: "ime_kolone",
      });
    }

    if (name.includes("gorivo")) {
      if (colName.includes("litri") || colName.includes("kapacitet")) {
        findings.push({
          tip: "kolona",
          entitet: name,
          atribut: colName,
          zakljucak: `Kolicina u litrima. Tip: ${colType}. Podrazumevana vrednost >= 0.`,
          confidence: 0.85,
          nauceno_od: "ime_kolone",
        });
      }
      if (colName.includes("alarm")) {
        findings.push({
          tip: "kolona",
          entitet: name,
          atribut: colName,
          zakljucak: "Kriticni nivo — kada se aktivira upozorenje da treba dopuniti.",
          confidence: 0.8,
          nauceno_od: "ime_kolone",
        });
      }
      if (colName.includes("pistolj") || colName.includes("brojac")) {
        findings.push({
          tip: "kolona",
          entitet: name,
          atribut: colName,
          zakljucak: "Brojac koji meri izdate litre (verovatno pumpa/pistolj za sipanje).",
          confidence: 0.7,
          nauceno_od: "ime_kolone",
        });
      }
    }
  }

  if (table.sample_data.length > 0) {
    const first = table.sample_data[0];
    const keys = Object.keys(first);

    const allNull = keys.every((k) => first[k] === null);
    if (allNull) {
      findings.push({
        tip: "pravilo",
        entitet: name,
        atribut: null,
        zakljucak: "Trenutno nema podataka u tabeli (prazna ili sve NULL).",
        confidence: 0.9,
        nauceno_od: "podaci",
      });
    }

    if (name.includes("gorivo") && first["trenutno_stanje_litri"] !== undefined) {
      const trenutno = Number(first["trenutno_stanje_litri"]);
      const alarm = Number(first["alarm_nivo_litri"] || 0);
      const kapacitet = Number(first["kapacitet_litri"] || 1);

      if (!isNaN(trenutno) && !isNaN(alarm)) {
        if (trenutno < alarm) {
          findings.push({
            tip: "pravilo",
            entitet: name,
            atribut: null,
            zakljucak: `Trenutno stanje (${trenutno}L) je ispod alarmnog nivoa (${alarm}L). Rezervoar je na kriticnom nivou — treba naruciti gorivo.`,
            confidence: 0.9,
            nauceno_od: "podaci",
          });
        } else {
          const procenat = ((trenutno / kapacitet) * 100).toFixed(1);
          findings.push({
            tip: "pravilo",
            entitet: name,
            atribut: null,
            zakljucak: `Rezervoar je na ${procenat}% (${trenutno}L od ${kapacitet}L). Alarm na ${alarm}L.`,
            confidence: 0.85,
            nauceno_od: "podaci",
          });
        }
      }
    }

    // Pametna analiza v3_app_settings (podesavanja i raspored)
    if (name.includes("app_settings")) {
      if (first["bc_custom_by_day"] || first["vs_custom_by_day"]) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: `U ovoj tabeli se cuvaju podesavanja rasporeda polazaka (red voznje). Postoje JSON polja bc_custom_by_day i vs_custom_by_day sa vremenima polazaka.`,
          confidence: 0.85,
          nauceno_od: "podaci",
        });

        // Izdvoji konkretna vremena iz JSON-a
        const bcJson = first["bc_custom_by_day"] as Record<string, string[]> | undefined;
        const vsJson = first["vs_custom_by_day"] as Record<string, string[]> | undefined;

        if (bcJson && typeof bcJson === "object") {
          for (const [dan, vremena] of Object.entries(bcJson)) {
            if (Array.isArray(vremena) && vremena.length > 0) {
              findings.push({
                tip: "pravilo",
                entitet: name,
                atribut: "bc_custom_by_day",
                zakljucak: `BC (Bela Crkva) polasci u ${dan}: ${vremena.join(", ")}.`,
                confidence: 0.9,
                nauceno_od: "podaci",
              });
            }
          }
          const sviDani = Object.keys(bcJson).join(", ");
          findings.push({
            tip: "pravilo",
            entitet: name,
            atribut: "bc_custom_by_day",
            zakljucak: `BC (Bela Crkva) raspored važi za dane: ${sviDani}. Svaki dan ima razlicite ili iste termine.`,
            confidence: 0.85,
            nauceno_od: "podaci",
          });
        }

        if (vsJson && typeof vsJson === "object") {
          for (const [dan, vremena] of Object.entries(vsJson)) {
            if (Array.isArray(vremena) && vremena.length > 0) {
              findings.push({
                tip: "pravilo",
                entitet: name,
                atribut: "vs_custom_by_day",
                zakljucak: `VS (Vrsac) polasci u ${dan}: ${vremena.join(", ")}.`,
                confidence: 0.9,
                nauceno_od: "podaci",
              });
            }
          }
          const sviDani = Object.keys(vsJson).join(", ");
          findings.push({
            tip: "pravilo",
            entitet: name,
            atribut: "vs_custom_by_day",
            zakljucak: `VS (Vrsac) raspored važi za dane: ${sviDani}. Svaki dan ima razlicite ili iste termine.`,
            confidence: 0.85,
            nauceno_od: "podaci",
          });
        }
      }
      if (first["neradni_dani"]) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: "neradni_dani",
          zakljucak: "Neradni dani se cuvaju kao JSON niz sa datumima i scope poljima.",
          confidence: 0.8,
          nauceno_od: "podaci",
        });
      }
      if (first["active_week_start"] && first["active_week_end"]) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: `Aktivna operativna nedelja: ${first["active_week_start"]} do ${first["active_week_end"]}.`,
          confidence: 0.85,
          nauceno_od: "podaci",
        });
      }
      if (first["latest_version_android"] || first["latest_version_ios"]) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: "Ova tabela takodje sadrzi informacije o verziji aplikacije i store URL-ovima.",
          confidence: 0.75,
          nauceno_od: "podaci",
        });
      }
    }

    // Pametna analiza v3_kapacitet_slots (red voznje, raspored mesta)
    if (name.includes("kapacitet")) {
      const slotKeys = keys.filter((k) => k.includes("slot") || k.includes("termin") || k.includes("vreme") || k.includes("at"));
      if (slotKeys.length > 0) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: `Ova tabela predstavlja raspored mesta (red voznje). Ima ${slotKeys.length} kolona vezano za termine/vremena.`,
          confidence: 0.85,
          nauceno_od: "podaci",
        });
      }
    }

    // Pametna analiza v3_zahtevi (zahtevi za voznju)
    if (name.includes("zahtevi") && first["status"] !== undefined) {
      const statusi = new Set<string>();
      for (const row of table.sample_data) {
        if (row["status"]) statusi.add(String(row["status"]));
      }
      const statusList = Array.from(statusi).join(", ");
      if (statusList) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: "status",
          zakljucak: `Statusi zahteva: ${statusList}. Ovo su razlicita stanja u kojima moze biti zahtev.`,
          confidence: 0.8,
          nauceno_od: "podaci",
        });
      }
      if (first["trazeni_polazak_at"] || first["polazak_at"]) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: "Zahtevi sadrze vreme polaska (trazeni i potvrdjeni). Ovo je vezano za raspored/red voznje.",
          confidence: 0.8,
          nauceno_od: "podaci",
        });
      }
    }

    // Pametna analiza v3_finansije (prihodi i rashodi)
    if (name.includes("finansije")) {
      if (first["tip"] !== undefined) {
        const tipovi = new Set<string>();
        let ukupanPrihod = 0;
        let ukupanRashod = 0;
        for (const row of table.sample_data) {
          const tip = String(row["tip"] ?? "");
          if (tip) tipovi.add(tip);
          const iznos = Number(row["iznos"] || 0);
          if (tip === "prihod") ukupanPrihod += iznos;
          if (tip === "rashod") ukupanRashod += iznos;
        }
        const tipList = Array.from(tipovi).join(", ");
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: "tip",
          zakljucak: `Finansije imaju tipove: ${tipList}. Svaki zapis je ili prihod ili rashod.`,
          confidence: 0.85,
          nauceno_od: "podaci",
        });
        if (ukupanPrihod > 0 || ukupanRashod > 0) {
          findings.push({
            tip: "pravilo",
            entitet: name,
            atribut: null,
            zakljucak: `Ukupan prihod iz uzorka: ${ukupanPrihod.toFixed(2)}, ukupan rashod: ${ukupanRashod.toFixed(2)}.`,
            confidence: 0.8,
            nauceno_od: "podaci",
          });
        }
      }
      if (first["isplata_iz"] !== undefined) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: "isplata_iz",
          zakljucak: "Finansijski zapisi beleze izvor isplate (npr. 'pazar' za gotovinsko placanje).",
          confidence: 0.75,
          nauceno_od: "podaci",
        });
      }
      if (first["broj_voznji"] !== undefined) {
        const ukupnoVoznji = table.sample_data.reduce((sum, row) => sum + Number(row["broj_voznji"] || 0), 0);
        const ukupnoOtkazivanja = table.sample_data.reduce((sum, row) => sum + Number(row["broj_otkazivanja"] || 0), 0);
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: `Iz finansijskih zapisa: ukupno voznji ${ukupnoVoznji}, otkazivanja ${ukupnoOtkazivanja}.`,
          confidence: 0.8,
          nauceno_od: "podaci",
        });
      }
      if (first["mesec"] !== undefined && first["godina"] !== undefined) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: null,
          zakljucak: "Finansije se filtriraju po mesecu i godini za izvestaje.",
          confidence: 0.75,
          nauceno_od: "podaci",
        });
      }
      if (first["naplaceno_by"] !== undefined) {
        findings.push({
          tip: "pravilo",
          entitet: name,
          atribut: "naplaceno_by",
          zakljucak: "Kolona 'naplaceno_by' pokazuje ko je naplatio (vozac). Povezano sa tabelom v3_auth.",
          confidence: 0.75,
          nauceno_od: "podaci",
        });
      }
      if (first["poslednja_dopuna"] !== undefined) {
        const ukupnoDopuna = table.sample_data.reduce((sum, row) => sum + Number(row["poslednja_dopuna"] || 0), 0);
        if (ukupnoDopuna > 0) {
          findings.push({
            tip: "pravilo",
            entitet: name,
            atribut: "poslednja_dopuna",
            zakljucak: `Ukupno dopuna iz uzorka: ${ukupnoDopuna.toFixed(2)}. Ovo je iznos koji je putnik doplatio nakon inicijalne naplate.`,
            confidence: 0.75,
            nauceno_od: "podaci",
          });
        }
      }
    }

    // Analiza pojedinacnih redova za sve tabele
    const skipCols = new Set(["id", "created_at", "updated_at", "deleted_at"]);
    for (const row of table.sample_data) {
      if (name.includes("auth")) {
        const ime = row["ime"] || row["full_name"] || row["name"] || row["username"];
        const tel = row["telefon"] || row["phone"];
        const uloga = row["uloga"] || row["role"] || row["tip"];
        const grad = row["grad"] || row["city"];
        if (ime) {
          findings.push({
            tip: "podatak",
            entitet: name,
            atribut: "korisnik",
            zakljucak: `Korisnik: ${ime}${tel ? ", tel: " + tel : ""}${uloga ? ", uloga: " + uloga : ""}${grad ? ", grad: " + grad : ""}.`,
            confidence: 0.9,
            nauceno_od: "podaci",
          });
        }
      } else if (name.includes("zahtevi")) {
        const putnik = row["ime_putnika"] || row["putnik"] || row["korisnik_ime"] || row["ime"];
        const vozacId = row["vozac_id"] || row["dodeljen_vozac_id"];
        const polazak = row["trazeni_polazak_at"] || row["polazak_at"];
        const cena = row["cena"] || row["iznos"];
        const status = row["status"];
        const odLok = row["od_lokacija"] || row["od"];
        const doLok = row["do_lokacija"] || row["do"];
        if (putnik || vozacId) {
          findings.push({
            tip: "podatak",
            entitet: name,
            atribut: null,
            zakljucak: `Zahtev: ${putnik ? "putnik " + putnik : "zahtev"}${odLok ? " od " + odLok : ""}${doLok ? " do " + doLok : ""}${polazak ? ", polazak: " + polazak : ""}${cena ? ", cena: " + cena : ""}${status ? ", status: " + status : ""}${vozacId ? ", vozac_id: " + vozacId : ""}.`,
            confidence: 0.9,
            nauceno_od: "podaci",
          });
        }
      } else if (name.includes("finansije")) {
        const tip = row["tip"];
        const iznos = row["iznos"];
        const isplataIz = row["isplata_iz"];
        const naplacenoBy = row["naplaceno_by"];
        const mesec = row["mesec"];
        const godina = row["godina"];
        const datum = row["datum"] || row["created_at"];
        if (iznos !== undefined) {
          findings.push({
            tip: "podatak",
            entitet: name,
            atribut: null,
            zakljucak: `Finansije: ${tip || "transakcija"} od ${iznos}${isplataIz ? " din, placeno iz: " + isplataIz : ""}${naplacenoBy ? ", naplatio: " + naplacenoBy : ""}${datum ? ", datum: " + datum : ""}${mesec ? ", mesec: " + mesec : ""}${godina ? ", godina: " + godina : ""}.`,
            confidence: 0.9,
            nauceno_od: "podaci",
          });
        }
      } else if (name.includes("racuni")) {
        const iznos = row["iznos"];
        const status = row["status"];
        const datum = row["datum"] || row["created_at"];
        const korisnikId = row["korisnik_id"] || row["user_id"];
        if (iznos !== undefined) {
          findings.push({
            tip: "podatak",
            entitet: name,
            atribut: null,
            zakljucak: `Racun: iznos ${iznos}${status ? ", status: " + status : ""}${datum ? ", datum: " + datum : ""}${korisnikId ? ", korisnik_id: " + korisnikId : ""}.`,
            confidence: 0.9,
            nauceno_od: "podaci",
          });
        }
      } else {
        const parts: string[] = [];
        for (const [key, val] of Object.entries(row)) {
          if (skipCols.has(key)) continue;
          if (val === null || val === undefined) continue;
          parts.push(`${key}=${val}`);
        }
        if (parts.length > 0) {
          findings.push({
            tip: "podatak",
            entitet: name,
            atribut: null,
            zakljucak: `Red iz ${name}: ${parts.join(", ")}.`,
            confidence: 0.7,
            nauceno_od: "podaci",
          });
        }
      }
    }
  }

  return findings;
}

async function saveFindings(supabase: SupabaseClient, findings: Array<{
  tip: string;
  entitet: string;
  atribut: string | null;
  zakljucak: string;
  confidence: number;
  nauceno_od: string;
}>): Promise<number> {
  if (findings.length === 0) return 0;

  // Batch deduplikacija — uzmi sve postojece za entitete koje imamo
  const entiteti = [...new Set(findings.map((f) => f.entitet))];
  const { data: existingRows } = await supabase
    .from("ai_znanje")
    .select("entitet,atribut,zakljucak")
    .in("entitet", entiteti);

  const existingSet = new Set(
    (existingRows || []).map((e) => `${e.entitet}|${e.atribut || ""}|${e.zakljucak}`)
  );

  const toInsert = findings.filter(
    (f) => !existingSet.has(`${f.entitet}|${f.atribut || ""}|${f.zakljucak}`)
  );

  if (toInsert.length === 0) return 0;

  // Batch insert po 500
  const BATCH_SIZE = 500;
  let saved = 0;
  for (let i = 0; i < toInsert.length; i += BATCH_SIZE) {
    const batch = toInsert.slice(i, i + BATCH_SIZE);
    const { error } = await supabase.from("ai_znanje").insert(batch);
    if (!error) saved += batch.length;
  }

  return saved;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase environment variables" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body = await req.json().catch(() => ({}));
    const action = body.action || "ucisve";
    const entitet = body.entitet || null;

    let allFindings: Array<{
      tip: string;
      entitet: string;
      atribut: string | null;
      zakljucak: string;
      confidence: number;
      nauceno_od: string;
    }> = [];

    if (action === "ucisve") {
      const schema = await getSchema(supabase);
      for (const table of schema) {
        const findings = analyzeTable(table);
        allFindings = allFindings.concat(findings);
      }
    } else if (action === "uci" && entitet) {
      const schema = await getSchema(supabase);
      const table = schema.find((t) => t.table_name === entitet);
      if (!table) {
        return new Response(
          JSON.stringify({ error: `Tabela ${entitet} nije pronadjena` }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      allFindings = analyzeTable(table);
    } else if (action === "znanje") {
      const { data, error } = await supabase
        .from("ai_znanje")
        .select("*")
        .order("confidence", { ascending: false });

      if (error) throw error;

      return new Response(
        JSON.stringify({ znanje: data }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else if (action === "potvrdi") {
      const znanjeId = body.id;
      const noviZakljucak = body.zakljucak || null;

      if (!znanjeId) {
        return new Response(
          JSON.stringify({ error: "Nedostaje id za potvrdu" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const updateData: Record<string, unknown> = { potvrdjeno: true, confidence: 0.95 };
      if (noviZakljucak) updateData.zakljucak = noviZakljucak;

      const { data, error } = await supabase
        .from("ai_znanje")
        .update(updateData)
        .eq("id", znanjeId)
        .select()
        .single();

      if (error) throw error;

      return new Response(
        JSON.stringify({ message: "Znanje potvrdjeno", znanje: data }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else if (action === "odbij") {
      const znanjeId = body.id;
      if (!znanjeId) {
        return new Response(
          JSON.stringify({ error: "Nedostaje id za odbijanje" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data, error } = await supabase
        .from("ai_znanje")
        .update({ confidence: 0.1 })
        .eq("id", znanjeId)
        .select()
        .single();

      if (error) throw error;

      return new Response(
        JSON.stringify({ message: "Znanje odbaceno (confidence smanjen)", znanje: data }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else if (action === "nauci_chat") {
      const tip = body.tip || "hipoteza";
      const entitet = body.entitet;
      const atribut = body.atribut || null;
      const zakljucak = body.zakljucak;

      if (!entitet || !zakljucak) {
        return new Response(
          JSON.stringify({ error: "Nedostaje entitet ili zakljucak" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: existing } = await supabase
        .from("ai_znanje")
        .select("id")
        .eq("entitet", entitet)
        .eq("atribut", atribut || "")
        .eq("zakljucak", zakljucak)
        .maybeSingle();

      if (existing) {
        return new Response(
          JSON.stringify({ message: "Ovo znanje vec postoji", znanje: existing }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data, error } = await supabase
        .from("ai_znanje")
        .insert({
          tip,
          entitet,
          atribut,
          zakljucak,
          confidence: 0.9,
          potvrdjeno: true,
          nauceno_od: "chat",
        })
        .select()
        .single();

      if (error) throw error;

      return new Response(
        JSON.stringify({ message: "Znanje nauceno iz chata", znanje: data }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const saved = await saveFindings(supabase, allFindings);

    return new Response(
      JSON.stringify({
        message: `AI je analizirao bazu. Pronadjeno ${allFindings.length} hipoteza, sacuvano ${saved} novih.`,
        hipoteze: allFindings,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
