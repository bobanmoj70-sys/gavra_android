# Raspodela

Ključ termina: `dan + grad + vreme`

---

## 1. Raspodela termina vozaču

Admin dodeli vozača terminu → vozač vidi **ceo termin sa svim putnicima** u njemu.

- Tabela: `vozac_raspored`
- Svi putnici tog termina automatski idu tom vozaču
- Vozač ne vidi putnike iz termina koji nije njegov

**TODO:**
- [ ] `filterKombinovan` — svi putnici termina idu vozaču termina, čak i bez `dodjelen_vozac`
- [ ] Termin mora biti vidljiv u vozačevom bottom nav baru

---

## 2. Raspodela putnika vozaču (individualna)

Admin dodeli pojedinačnog putnika vozaču — **samo ako termin NIJE raspoređen**.

- Tabela: `vozac_putnik`
- Ključ provere: `dan + grad + vreme` (putnikov termin)
- Ako termin (`dan + grad + vreme`) postoji u `vozac_raspored` → individualna raspodela putnika je **zabranjena**
- Ako termin nije raspoređen → individualna raspodela je dozvoljena

**Prioritet:** raspodela termina > raspodela putnika

**TODO:**
- [ ] Ako termin postoji u `vozac_raspored` → sakrij dugme za individualnu raspodelu pored putnika
