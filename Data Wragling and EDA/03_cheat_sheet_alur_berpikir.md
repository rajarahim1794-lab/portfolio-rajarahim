# Cheat Sheet: Alur Berpikir Data Wrangling & EDA
### Pendamping file `02_wrangling_dan_eda.sql`

Ini bukan jawaban langsung, tapi **jalan pikiran** yang bisa dipakai setiap kali menghadapi data mentah — di latihan ini maupun di pekerjaan nyata nanti.

---

## 0. Pertanyaan yang selalu ditanyakan di awal

Sebelum tulis query apapun, tanyakan ke diri sendiri:

1. **Apa pertanyaan bisnisnya?** (Di sini: "kenapa penjualan berubah sepanjang 2025?")
2. **Tabel apa saja yang terlibat, dan bagaimana hubungannya?** (`orders` → `customers`, `orders` → `products`)
3. **Satu baris di tiap tabel itu mewakili apa?** (1 baris `orders` = 1 transaksi. Kalau setelah JOIN jumlah baris berubah, ada yang salah.)

---

## 1. Roadmap Bagian A–E (urutan berpikir)

```
A. DISCOVERY
   "Data ini isinya apa, bentuknya seperti apa?"
   → SELECT * LIMIT, cek tipe kolom, hitung jumlah baris
        ↓
B. QUALITY CHECK
   "Di mana letak kotor/rusaknya data ini?"
   → cek NULL, cek duplikat, cek nilai aneh, cek konsistensi teks
   → JANGAN dibersihkan dulu, CATAT SEMUA temuan dulu
        ↓
C. WRANGLING
   "Bagaimana caranya data ini jadi rapi dan siap pakai?"
   → 1 masalah dari langkah B = 1 keputusan cleaning
   → buat tabel BARU (jangan timpa tabel mentah)
        ↓
D. VALIDASI
   "Apakah hasil cleaning saya benar, tidak ada yang hilang/berlipat?"
   → bandingkan jumlah baris sebelum vs sesudah, cek ulang duplikat & NULL
        ↓
E. EDA
   "Pola apa yang muncul, dan pertanyaan bisnis di atas terjawab tidak?"
   → statistik dasar → distribusi → bivariat → tren waktu → hipotesis
```

**Prinsip penting:** kalau di tahap E kamu menemukan hal aneh (misalnya angka yang tidak masuk akal), itu **wajar** — kembali ke tahap B/C, bukan tanda kamu salah. Wrangling dan EDA memang bolak-balik.

---

## 2. Checklist Quality Check (Bagian B) — pola masalah yang selalu dicek

Pakai daftar ini setiap kali dapat tabel baru, di latihan ini maupun nanti di kerjaan asli:

| Yang dicek | Query pattern |
|---|---|
| Duplikat baris | `COUNT(*) - COUNT(DISTINCT id)` |
| Nilai kosong | `COUNT(*) FILTER (WHERE kolom IS NULL)` |
| Nilai tidak valid (negatif/nol) | `COUNT(*) FILTER (WHERE angka <= 0)` |
| Penulisan tidak konsisten | `GROUP BY kolom` lalu lihat semua variasinya |
| Spasi tersembunyi | bungkus dengan `'[' \|\| kolom \|\| ']'` |
| Tanggal aneh (masa depan/masa lalu ekstrem) | `WHERE tanggal > CURRENT_DATE` |
| Baris "yatim" (foreign key tidak ada pasangannya) | `LEFT JOIN ... WHERE induk.id IS NULL` |
| Tipe data salah (angka tersimpan sebagai teks) | lihat `information_schema.columns` |

---

## 3. Keputusan Wrangling (Bagian C) — pola solusi

| Masalah | Solusi umum |
|---|---|
| Duplikat | `ROW_NUMBER() OVER (PARTITION BY id ORDER BY id)`, ambil `rn = 1` |
| Teks tidak konsisten | `TRIM()` + `LOWER()`/`INITCAP()`, lalu `CASE WHEN` untuk kasus khusus |
| Angka tersimpan sebagai teks | `REGEXP_REPLACE(kolom, '[^0-9]', '', 'g')::numeric` |
| Tanggal format campur | deteksi pola dengan regex (`~`), lalu `CASE WHEN ... THEN ... ELSE TO_DATE(...)` |
| NULL numerik yang wajar diisi 0 | `COALESCE(kolom, 0)` |
| NULL kategori yang perlu label | `COALESCE(kolom, 'tidak diketahui')` |
| Baris tidak valid | `WHERE` di query final — buang, jangan `UPDATE` tabel mentah |
| Gabung tabel | `JOIN` — validasi jumlah baris sebelum & sesudah |

**Aturan emas:** tabel `raw_*` tidak pernah diubah. Semua hasil kerja masuk ke tabel `*_clean` atau `fact_*` yang baru.

---

## 4. Validasi (Bagian D) — 3 pertanyaan wajib

1. **Jumlah baris masuk akal?** `raw_order_unik` harus ≥ `orders_clean` (selisihnya = baris yang sengaja dibuang, dan itu harus bisa dijelaskan).
2. **Tidak ada duplikat baru?** Ulangi cek `COUNT(*) - COUNT(DISTINCT id)`.
3. **Tidak ada kebocoran dari JOIN?** `COUNT(*)` di tabel gabungan harus sama dengan tabel transaksi asal, kecuali memang berniat memperbesar (one-to-many).

---

## 5. Pola Berpikir EDA (Bagian E)

Urutan yang dipakai profesional, dari yang paling umum ke paling spesifik:

```
1. Statistik dasar     → "Angka normalnya di kisaran berapa?" (AVG, MEDIAN, MIN, MAX)
2. Distribusi           → "Sebarannya seperti apa? Ada yang aneh?" (GROUP BY + COUNT)
3. Deteksi outlier      → "Ada nilai yang mencurigakan?" (metode IQR)
4. Bivariat             → "Variabel A ada hubungannya dengan B tidak?" (GROUP BY 2 kolom)
5. Tren waktu           → "Berubah dari waktu ke waktu tidak?" (GROUP BY bulan + LAG)
6. Segmentasi           → "Di kelompok mana masalah ini terjadi?" (breakdown per kategori/kota)
7. Hipotesis            → tulis 1-2 kalimat kesimpulan sementara
```

**Trik IQR untuk outlier** (dipakai di E3):
```sql
batas_atas = Q3 + 1.5 × (Q3 − Q1)
batas_bawah = Q1 − 1.5 × (Q3 − Q1)
```
Nilai di luar rentang ini layak dicurigai — tapi selalu **cek dulu**, jangan langsung hapus (bisa jadi itu kejadian nyata, bukan error).

**Trik menemukan "di mana" masalah terjadi** (dipakai di E10): pecah data jadi dua periode/kelompok, lalu bandingkan sisi-sisi mana yang beda paling jauh. Ini cara paling cepat mengubah "penjualan turun" menjadi "penjualan kategori X turun, di kota Y".

---

## 6. Petunjuk untuk 7 Soal Latihan Mandiri (Bagian F)

Bukan jawaban, tapi arah SQL yang dipakai:

| No | Yang ditanya | Fungsi/pola kunci |
|---|---|---|
| 1 | % order dibuang & alasannya | Hitung terpisah tiap kondisi WHERE di langkah C3 dengan `COUNT(*) FILTER (WHERE ...)` sebelum digabung jadi satu filter |
| 2 | Kota dengan penurunan Elektronik terbesar H1→H2 | `GROUP BY kota, periode` (seperti E10) lalu hitung selisih dengan `LAG()` atau self-join |
| 3 | Jarak hari daftar → order pertama | `JOIN customers_clean`, `MIN(tanggal_order) GROUP BY customer_id`, lalu `tanggal_order_pertama - tanggal_daftar` |
| 4 | Revenue per hari dalam seminggu | `EXTRACT(DOW FROM tanggal_order)` atau `TO_CHAR(tanggal_order, 'Day')` |
| 5 | Segmen nilai order | `CASE WHEN total_harga < 500000 THEN 'Kecil' WHEN total_harga <= 5000000 THEN 'Sedang' ELSE 'Besar' END` |
| 6 | Pelanggan tanpa order | `LEFT JOIN fact_orders ... WHERE fact_orders.order_id IS NULL` |
| 7 | Rata-rata bergerak 3 bulan | `AVG(revenue) OVER (ORDER BY bulan ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` |

---

## 7. Fungsi PostgreSQL yang paling sering dipakai di latihan ini

| Kategori | Fungsi |
|---|---|
| Bersih-bersih teks | `TRIM`, `LOWER`, `UPPER`, `INITCAP`, `REGEXP_REPLACE` |
| Tanggal | `TO_DATE`, `TO_CHAR`, `DATE_TRUNC`, `EXTRACT`, `CURRENT_DATE` |
| Hilangkan duplikat | `ROW_NUMBER() OVER (PARTITION BY ...)` |
| Agregat kondisional | `COUNT(*) FILTER (WHERE ...)`, `SUM(...) FILTER (WHERE ...)` |
| Statistik | `AVG`, `STDDEV`, `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` |
| Perbandingan antar baris/waktu | `LAG`, `LEAD`, window `ORDER BY` |
| Peringkat | `RANK`, `DENSE_RANK`, `ROW_NUMBER` |
| Nilai pengganti NULL | `COALESCE`, `NULLIF` |

---

## 8. Kesalahan yang paling sering terjadi (waspadai ini)

- Langsung `DELETE`/`UPDATE` tabel `raw_` — **jangan**, selalu buat tabel baru.
- Lupa cek jumlah baris setelah `JOIN` — bisa diam-diam berlipat ganda tanpa disadari.
- Menghapus outlier tanpa menyelidiki dulu apakah itu benar-benar error atau kejadian nyata (misal lonjakan saat promo).
- Berhenti di "kategori Elektronik turun" tanpa menelusuri lebih dalam (kota mana, bulan berapa persisnya, produk mana).
- Menyimpulkan sebab-akibat dari korelasi semata (data ini hanya bisa menunjukkan pola, bukan bukti penyebab pasti).

---

**Cara pakai cheat sheet ini:** setiap kali mengerjakan satu bagian di `02_wrangling_dan_eda.sql`, cek dulu bagian yang sesuai di sini. Kalau sudah selesai soal Bagian F, kirim query dan hasilnya — saya bisa cek apakah logikanya sudah tepat.
