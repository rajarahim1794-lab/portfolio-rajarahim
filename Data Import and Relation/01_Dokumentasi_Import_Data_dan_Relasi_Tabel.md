# Dokumentasi: Import Dataset & Membangun Relasi Tabel di PostgreSQL

Dokumen ini merangkum proses lengkap import dataset ke PostgreSQL (via DBeaver & pgAdmin), termasuk troubleshooting error yang umum ditemui, serta cara membangun relasi antar tabel dari data mentah (studi kasus dataset Olist).

---

## 1. Dua Skenario Import Dataset

### Skenario A: Dataset berupa file SQL (schema.sql + data.sql, atau satu file gabungan)
Contoh: Pagila, Chinook.

**Langkah umum:**
1. Buat database kosong terlebih dahulu (klik kanan Databases > Create > Database).
2. Buka SQL Editor / Query Tool yang terhubung ke database tersebut.
3. Buka file `.sql` (ikon folder di toolbar editor).
4. Jalankan **seluruh script** (Execute SQL Script, bukan Execute Statement satu baris).
5. Cek tab **Messages** — pastikan tidak ada tulisan `ERROR` berwarna merah dari atas sampai bawah.

### Skenario B: Dataset berupa file CSV (satu file per tabel)
Contoh: Olist.

**Langkah umum (DBeaver):**
1. Buat database kosong.
2. Navigasi ke `Databases > [nama_db] > Schemas > public > Tables`.
3. Klik kanan **Tables** > Import Data.
4. Pilih CSV sebagai source, browse ke file.
5. Biarkan DBeaver menebak nama kolom & tipe data dari preview.
6. Klik Proceed/Finish.
7. Ulangi untuk setiap file CSV, masing-masing jadi tabel terpisah.

---

## 2. Error yang Sering Muncul & Solusinya

| Error | Penyebab | Solusi |
|---|---|---|
| `extension "vector" is not available` | Versi dataset terbaru pakai fitur AI (pgvector) yang tidak ter-install | Pakai versi dataset lama yang tidak butuh pgvector (cek tab "Releases" di GitHub repo dataset) |
| `syntax error at or near "1"` saat run file `*-data.sql` | File pakai perintah `COPY ... FROM stdin` yang tidak didukung penuh oleh GUI seperti pgAdmin Query Tool | Cari file alternatif `*-insert-data.sql` (kalau tersedia) yang pakai `INSERT` biasa, bukan `COPY` |
| `syntax error at or near "\"` (contoh: `\c namadb;`) | File mengandung **psql meta-command** yang hanya jalan di command-line psql, bukan di GUI | Buka file di text editor, hapus baris yang diawali `\` (misal `\c`, `\i`), simpan, lalu jalankan ulang |
| `DROP DATABASE cannot run inside a transaction block` | File mencoba `DROP DATABASE` / `CREATE DATABASE` di awal, padahal dijalankan sebagai satu transaksi besar oleh GUI | Hapus bagian `DROP DATABASE` dan `CREATE DATABASE` dari file (karena database sudah kamu buat manual sebelumnya), sisakan mulai dari bagian `CREATE TABLE` |
| `value too long for type character varying(256)` saat import CSV | Kolom otomatis dideteksi sebagai `VARCHAR(256)` padahal ada data yang lebih panjang (misal teks review customer) | `ALTER TABLE nama_tabel ALTER COLUMN nama_kolom TYPE TEXT;` lalu `TRUNCATE TABLE` dan import ulang ke tabel yang sudah ada (bukan bikin tabel baru) |
| `Can't parse numeric value` / kolom "geser" saat import CSV | CSV parser di DBeaver salah membaca baris yang mengandung koma/baris baru di dalam teks (misal komentar review yang panjang) | Gunakan fitur **Import/Export** bawaan pgAdmin (klik kanan tabel > Import/Export Data), karena parsingnya memakai command native PostgreSQL (`COPY`) yang lebih ketat mengikuti standar CSV |
| Database tidak muncul di DBeaver padahal sudah dibuat di pgAdmin | Setting koneksi DBeaver hanya menampilkan satu database default | Edit Connection > centang **"Show all databases"** di tab Main, lalu refresh koneksi |

---

## 3. Cara Menghubungkan DBeaver ke Database yang Sudah Dibuat di pgAdmin

Karena pgAdmin dan DBeaver sama-sama terhubung ke server PostgreSQL yang sama, database yang dibuat lewat salah satu tool otomatis terlihat di tool lainnya — tidak perlu import ulang.

1. Di DBeaver, pastikan sudah ada koneksi PostgreSQL yang mengarah ke `localhost:5432` (port yang sama dengan yang dipakai pgAdmin).
2. Edit Connection > tab Main > centang **"Show all databases"**.
3. Klik kanan koneksi > Refresh.
4. Expand **Databases**, database yang dibuat di pgAdmin akan muncul di sana.

---

## 4. Menghubungkan ke Database Online (URL / SSH)

### Via URL (contoh: Neon, Supabase)
1. Daftar akun gratis di layanan tersebut, buat project baru.
2. Copy connection string yang diberikan (format: `postgresql://user:password@host/dbname?sslmode=require`).
3. Di DBeaver, New Connection > PostgreSQL > pilih **"Connect by: URL"** > paste connection string.
4. Test Connection > Finish.

### Via SSH Tunnel (untuk server privat yang tidak expose port database ke publik)
1. Siapkan kredensial SSH (host/IP, username, password atau private key).
2. Buat koneksi PostgreSQL seperti biasa, Host diisi `localhost`.
3. Buka tab **SSH** di jendela konfigurasi koneksi, centang "Use SSH Tunnel".
4. Isi Host/IP server, Port 22, username, dan metode autentikasi SSH.
5. Test Tunnel Configuration, lalu Test Connection.

---

## 5. Membangun Relasi Antar Tabel dari Data Mentah (Studi Kasus: Olist)

Saat dataset berupa CSV mentah tanpa struktur relasi, ikuti tahapan berikut:

### Langkah 1: Pahami logika bisnis / peta relasi
Gambar dulu di kertas/diagram sederhana hubungan antar entitas sebelum menulis SQL apapun. Contoh (Olist):

```
customers (1) ──────< orders
orders (1) ──────< order_items
orders (1) ──────< order_payments
orders (1) ──────< order_reviews
products (1) ──────< order_items
sellers (1) ──────< order_items
products (banyak) >──< product_category_name_translation
```

### Langkah 2: Verifikasi kolom kandidat Primary Key
```sql
-- Kalau COUNT(*) = COUNT(DISTINCT kolom), kolom itu aman jadi Primary Key
SELECT COUNT(*), COUNT(DISTINCT customer_id) FROM nama_tabel;
```

### Langkah 3: Tambahkan Primary Key ke tabel induk
```sql
ALTER TABLE customers ADD PRIMARY KEY (customer_id);
ALTER TABLE orders ADD PRIMARY KEY (order_id);
ALTER TABLE products ADD PRIMARY KEY (product_id);
```

### Langkah 4: Tambahkan Foreign Key untuk menghubungkan tabel
```sql
ALTER TABLE orders 
ADD CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

ALTER TABLE order_items 
ADD CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE order_items 
ADD CONSTRAINT fk_product FOREIGN KEY (product_id) REFERENCES products(product_id);
```

### Langkah 5: Perbaiki tipe data yang salah tebak
```sql
-- Cek tipe data sekarang
SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'orders';

-- Ubah dari text ke tipe yang benar
ALTER TABLE orders 
ALTER COLUMN order_purchase_timestamp TYPE TIMESTAMP USING order_purchase_timestamp::TIMESTAMP;

ALTER TABLE order_items 
ALTER COLUMN price TYPE NUMERIC USING price::NUMERIC;
```

### Langkah 6: Verifikasi visual & fungsional
- Di DBeaver: klik kanan database > **View Diagram** untuk melihat ER Diagram otomatis dari FK yang sudah dibuat.
- Test dengan query JOIN lintas tabel untuk pastikan semua relasi berfungsi:
```sql
SELECT c.customer_state, COUNT(*) AS jumlah_order
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY jumlah_order DESC;
```

---

## Ringkasan Tools yang Dipakai

| Tool | Fungsi Utama |
|---|---|
| **DBeaver** | GUI multi-database, bagus untuk import CSV otomatis & lihat ER Diagram |
| **pgAdmin** | GUI khusus PostgreSQL, lebih stabil untuk file SQL dengan `COPY` dan CSV kompleks |
| **EXPLAIN ANALYZE** | Perintah SQL untuk cek performa query (dibahas lebih lanjut di file latihan) |
