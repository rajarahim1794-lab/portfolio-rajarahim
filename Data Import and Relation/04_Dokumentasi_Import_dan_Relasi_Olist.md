# Dokumentasi Lengkap: Import & Relasi Tabel Dataset Olist (dari Awal)

Dataset Olist adalah data e-commerce mentah berupa 9 file CSV terpisah, TANPA struktur relasi apapun. Dokumen ini merangkum seluruh proses dari download sampai dataset siap dipakai analisis, termasuk semua error yang mungkin muncul beserta solusinya.

**Sumber dataset:** https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce (butuh akun Kaggle gratis)

---

## Fase 0: Persiapan

1. Download dataset dari Kaggle, extract ZIP-nya.
2. Kamu akan mendapat 9 file CSV:
   - `olist_customers_dataset.csv`
   - `olist_orders_dataset.csv`
   - `olist_order_items_dataset.csv`
   - `olist_order_payments_dataset.csv`
   - `olist_order_reviews_dataset.csv`
   - `olist_products_dataset.csv`
   - `olist_sellers_dataset.csv`
   - `olist_geolocation_dataset.csv`
   - `product_category_name_translation.csv`
3. Buat database baru bernama `olist` (lewat pgAdmin atau DBeaver, klik kanan Databases > Create > Database).

---

## Fase 1: Import 9 CSV sebagai Tabel Mentah

**Via DBeaver (cara utama):**
1. Di Database Navigator, masuk ke `olist > Schemas > public > Tables`.
2. Klik kanan tepat pada node **Tables** (bukan di level database) > **Import Data**.
3. Pilih CSV sebagai source, browse ke file pertama.
4. Biarkan DBeaver menebak nama kolom & tipe data dari preview — klik Proceed.
5. Ulangi untuk **semua 9 file**, masing-masing jadi tabel terpisah dengan nama sesuai nama file.
6. Refresh Tables, pastikan 9 tabel sudah muncul.

> **Kenapa lewat Tables, bukan langsung database?** Supaya import pasti masuk ke schema `public` yang benar, terutama kalau nanti bekerja dengan database yang punya banyak schema sekaligus.

---

## Fase 2: Error yang Muncul Saat Import & Solusinya

### Error 1: `ERROR: value too long for type character varying(256)`
**Kapan terjadi:** Saat import `olist_order_reviews_dataset.csv`, karena kolom `review_comment_message` berisi teks review yang panjangnya melebihi 256 karakter, padahal DBeaver menebak tipenya `VARCHAR(256)` dari sample data awal.

**Solusi:**
```sql
-- 1. Ubah tipe kolom jadi TEXT (tanpa batas panjang)
ALTER TABLE public.olist_order_reviews_dataset ALTER COLUMN review_comment_message TYPE TEXT;
ALTER TABLE public.olist_order_reviews_dataset ALTER COLUMN review_comment_title TYPE TEXT;

-- 2. Kosongkan tabel dari data yang mungkin sudah setengah masuk
TRUNCATE TABLE public.olist_order_reviews_dataset;
```
Lalu import ulang CSV yang sama, tapi pilih **"Existing Table"** (bukan New Table) supaya tipe `TEXT` yang sudah diperbaiki tidak ditimpa lagi.

### Error 2: `Can't parse numeric value ... Illegal embedded sign character`
**Kapan terjadi:** Masih di file review, karena ada teks komentar yang mengandung karakter khusus (koma/baris baru di dalam kutip) yang membuat parser CSV DBeaver salah membaca batas kolom, sehingga teks "geser" masuk ke kolom yang seharusnya angka/tanggal.

**Solusi:** Gunakan fitur **Import/Export bawaan pgAdmin** untuk file ini (parsernya memakai command native PostgreSQL `COPY` yang lebih ketat mengikuti standar CSV):
1. `TRUNCATE TABLE public.olist_order_reviews_dataset;` lagi untuk membersihkan.
2. Buka pgAdmin, masuk ke tabel yang sama, klik kanan > **Import/Export Data...**
3. Set mode **Import**, pilih file CSV.
4. Di tab Options: Format = csv, Header = Yes, Delimiter = Comma, Quote character = `"`, Escape character = `"`.
5. Cek tab **Columns**, pastikan urutan kolom sesuai urutan di file CSV.
6. Klik Import.
7. Verifikasi: `SELECT COUNT(*) FROM public.olist_order_reviews_dataset;`

> **Prinsip umum:** kalau DBeaver gagal import CSV yang isinya teks kompleks (ulasan, komentar, deskripsi panjang), coba pgAdmin's Import/Export sebagai alternatif — parsernya lebih robust untuk kasus seperti ini.

---

## Fase 3: Memahami Peta Relasi (Sebelum Menulis SQL)

Pahami dulu logika bisnisnya sebelum bikin Primary Key/Foreign Key:

```
customers (1) ──────< orders            (1 customer bisa banyak order)
orders (1) ──────< order_items          (1 order bisa banyak item)
orders (1) ──────< order_payments       (1 order bisa >1 metode bayar)
orders (1) ──────< order_reviews        (biasanya 1 review per order)
products (1) ──────< order_items        (1 produk dijual di banyak item)
sellers (1) ──────< order_items         (1 seller jual banyak item)
products (banyak) >──< product_category_name_translation
```

---

## Fase 4: Menentukan & Menambahkan Primary Key

Cek dulu kolom kandidat PK benar-benar unik:
```sql
SELECT COUNT(*), COUNT(DISTINCT customer_id) FROM olist_customers_dataset;
SELECT COUNT(*), COUNT(DISTINCT order_id) FROM olist_orders_dataset;
```
Kalau kedua angka sama, kolom itu aman jadi Primary Key:
```sql
ALTER TABLE olist_customers_dataset ADD PRIMARY KEY (customer_id);
ALTER TABLE olist_orders_dataset ADD PRIMARY KEY (order_id);
ALTER TABLE olist_products_dataset ADD PRIMARY KEY (product_id);
ALTER TABLE olist_sellers_dataset ADD PRIMARY KEY (seller_id);
```

---

## Fase 5: Menambahkan Foreign Key (Menghubungkan Semua Tabel)

```sql
-- orders -> customers
ALTER TABLE olist_orders_dataset 
ADD CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES olist_customers_dataset(customer_id);

-- order_items -> orders, products, sellers (tabel penghubung utama)
ALTER TABLE olist_order_items_dataset 
ADD CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id);
ALTER TABLE olist_order_items_dataset 
ADD CONSTRAINT fk_product FOREIGN KEY (product_id) REFERENCES olist_products_dataset(product_id);
ALTER TABLE olist_order_items_dataset 
ADD CONSTRAINT fk_seller FOREIGN KEY (seller_id) REFERENCES olist_sellers_dataset(seller_id);

-- order_payments & order_reviews -> orders
ALTER TABLE olist_order_payments_dataset 
ADD CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id);
ALTER TABLE olist_order_reviews_dataset 
ADD CONSTRAINT fk_review_order FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id);

-- products -> kategori terjemahan (opsional, kalau ada mismatch data boleh dilewati)
ALTER TABLE olist_products_dataset 
ADD CONSTRAINT fk_category FOREIGN KEY (product_category_name) 
REFERENCES product_category_name_translation(product_category_name);
```

> Kalau langkah terakhir (kategori) error karena ada nilai NULL atau ketidakcocokan data (typo/beda kapital), boleh dilewati — kamu tetap bisa JOIN manual tanpa FK formal.

---

## Fase 6: Perbaiki Tipe Data yang Salah Tebak

```sql
-- Cek tipe data yang sekarang
SELECT column_name, data_type FROM information_schema.columns 
WHERE table_name = 'olist_orders_dataset';

-- Ubah kolom tanggal dari text ke timestamp
ALTER TABLE olist_orders_dataset 
ALTER COLUMN order_purchase_timestamp TYPE TIMESTAMP USING order_purchase_timestamp::TIMESTAMP;

-- Ubah kolom harga dari text ke numeric
ALTER TABLE olist_order_items_dataset 
ALTER COLUMN price TYPE NUMERIC USING price::NUMERIC;
```

---

## Fase 7: Verifikasi Akhir

**Visual:** Di DBeaver, klik kanan database `olist` > **View Diagram** untuk melihat ER Diagram otomatis berdasarkan FK yang sudah dibuat — cara cepat mengecek apakah desain relasi sudah benar.

**Fungsional — test query JOIN lintas 4 tabel:**
```sql
SELECT 
  c.customer_state,
  p.product_category_name,
  COUNT(*) AS jumlah_terjual,
  SUM(oi.price) AS total_revenue
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
JOIN olist_products_dataset p ON oi.product_id = p.product_id
GROUP BY c.customer_state, p.product_category_name
ORDER BY total_revenue DESC
LIMIT 10;
```
Kalau query ini berhasil jalan dan hasilnya masuk akal, dataset Olist sudah siap dipakai untuk analisis lebih lanjut.

---

## Ringkasan Alur (Checklist)

- [ ] Download & extract 9 file CSV dari Kaggle
- [ ] Buat database `olist`
- [ ] Import 9 CSV via DBeaver (Tables > Import Data)
- [ ] Perbaiki kolom `review_comment_message`/`title` jadi TEXT
- [ ] Import ulang file review yang bermasalah via pgAdmin Import/Export
- [ ] Cek keunikan kolom kandidat Primary Key
- [ ] Tambahkan Primary Key ke tabel induk
- [ ] Tambahkan Foreign Key untuk semua relasi
- [ ] Perbaiki tipe data (timestamp, numeric)
- [ ] Verifikasi lewat ER Diagram & query JOIN
