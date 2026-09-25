-- =====================================================================
-- 02_WRANGLING_DAN_EDA.SQL
-- Jalankan SETELAH 01_setup_data_mentah.sql
--
-- Cara pakai di DBeaver:
--   * Jalankan SATU query : letakkan kursor di query, tekan Ctrl+Enter
--   * Jalankan SEMUA      : Alt+X
--   * Disarankan jalankan bertahap, per bagian, sambil membaca hasilnya.
--   * Pakai editor yang SAMA selama latihan (supaya search_path tetap).
--
-- Alur:
--   A. Discovery           -> kenali data
--   B. Data quality check  -> temukan masalah
--   C. Wrangling           -> bersihkan & bentuk ulang
--   D. Validasi            -> pastikan hasil benar
--   E. EDA                 -> cari pola & hipotesis
--   F. Latihan mandiri
-- =====================================================================

SET search_path TO latihan;


-- =====================================================================
-- A. DISCOVERY: kenali data sebelum diubah
-- =====================================================================

-- A1. Berapa baris tiap tabel?
SELECT 'raw_customers' AS tabel, COUNT(*) AS jumlah_baris FROM raw_customers
UNION ALL
SELECT 'raw_products',  COUNT(*) FROM raw_products
UNION ALL
SELECT 'raw_orders',    COUNT(*) FROM raw_orders;

-- A2. Lihat contoh isi data
SELECT * FROM raw_orders    LIMIT 10;
SELECT * FROM raw_customers LIMIT 10;
SELECT * FROM raw_products;

-- A3. Kolom apa saja dan tipe datanya?
--     Perhatikan: tanggal & harga bertipe TEXT, bukan DATE / NUMERIC.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'latihan'
  AND table_name LIKE 'raw_%'
ORDER BY table_name, ordinal_position;


-- =====================================================================
-- B. DATA QUALITY CHECK: cari semua masalah SEBELUM membersihkan
-- =====================================================================

-- B1. Nilai kosong (NULL) dan nilai tidak valid di orders
SELECT
    COUNT(*)                                        AS total_baris,
    COUNT(*) FILTER (WHERE qty IS NULL)             AS qty_kosong,
    COUNT(*) FILTER (WHERE qty <= 0)                AS qty_nol_atau_negatif,
    COUNT(*) FILTER (WHERE metode_bayar IS NULL)    AS metode_bayar_kosong
FROM raw_orders;

-- B2. Duplikat di orders (order_id muncul lebih dari sekali)
SELECT COUNT(*) - COUNT(DISTINCT order_id) AS baris_duplikat
FROM raw_orders;

SELECT order_id, COUNT(*) AS muncul
FROM raw_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY order_id
LIMIT 10;

-- B3. Duplikat di customers
SELECT customer_id, COUNT(*) AS muncul
FROM raw_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- B4. Penulisan tidak konsisten (kategori teks)
SELECT status, COUNT(*) AS jumlah
FROM raw_orders GROUP BY status ORDER BY jumlah DESC;

-- Tanda kurung siku membantu melihat spasi tersembunyi
SELECT '[' || kota || ']' AS kota_mentah, COUNT(*) AS jumlah
FROM raw_customers GROUP BY kota ORDER BY kota;

SELECT '[' || kategori || ']' AS kategori_mentah, COUNT(*) AS jumlah
FROM raw_products GROUP BY kategori ORDER BY kategori;

-- B5. Format tanggal campur di customers
SELECT
    COUNT(*) FILTER (WHERE tanggal_daftar ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') AS format_yyyy_mm_dd,
    COUNT(*) FILTER (WHERE tanggal_daftar ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$') AS format_dd_mm_yyyy
FROM raw_customers;

-- B6. Tanggal order di masa depan
SELECT order_id, tanggal_order
FROM raw_orders
WHERE tanggal_order::date > CURRENT_DATE;

-- B7. Order yatim (customer_id tidak ada di tabel pelanggan)
SELECT DISTINCT o.customer_id
FROM raw_orders o
LEFT JOIN raw_customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- B8. Bukti bahaya JOIN pada data duplikat:
--     jumlah baris setelah join HARUS sama dengan jumlah baris orders.
--     Kalau lebih besar, ada baris yang berlipat ganda.
SELECT
    (SELECT COUNT(*) FROM raw_orders) AS baris_orders,
    (SELECT COUNT(*)
     FROM raw_orders o
     JOIN raw_customers c ON c.customer_id = o.customer_id) AS baris_setelah_join;

-- B9. Harga bertipe teks dengan awalan "Rp"
SELECT product_id, harga FROM raw_products ORDER BY product_id;

-- CATATAN TEMUAN (isi sendiri sambil jalan):
--   1. orders    : ada duplikat, qty kosong/nol/negatif, tanggal masa depan,
--                  customer yatim, status & metode bayar tidak konsisten
--   2. customers : ada duplikat, nama kota beragam, format tanggal campur
--   3. products  : kategori beda huruf besar/kecil + spasi, harga bertipe teks


-- =====================================================================
-- C. WRANGLING: bersihkan & bentuk ulang menjadi tabel siap analisis
--    Prinsip: JANGAN ubah tabel raw_. Buat tabel baru hasil cleaning.
-- =====================================================================

-- C1. customers_clean
--     Hapus duplikat, seragamkan kota, ubah tanggal ke tipe DATE
DROP TABLE IF EXISTS customers_clean;
CREATE TABLE customers_clean AS
WITH dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY customer_id) AS rn
    FROM raw_customers
)
SELECT
    customer_id,
    nama,
    CASE
        WHEN LOWER(TRIM(kota)) IN ('jakarta', 'dki jakarta') THEN 'Jakarta'
        WHEN LOWER(TRIM(kota)) IN ('surabaya', 'sby')        THEN 'Surabaya'
        ELSE INITCAP(TRIM(kota))
    END AS kota,
    CASE
        WHEN tanggal_daftar ~ '^[0-9]{4}-' THEN tanggal_daftar::date
        ELSE TO_DATE(tanggal_daftar, 'DD/MM/YYYY')
    END AS tanggal_daftar,
    email                                   -- NULL dibiarkan (tidak dipakai di analisis)
FROM dedup
WHERE rn = 1;

-- C2. products_clean
--     Seragamkan kategori, ubah harga teks menjadi angka
DROP TABLE IF EXISTS products_clean;
CREATE TABLE products_clean AS
SELECT
    product_id,
    nama_produk,
    INITCAP(TRIM(kategori))                         AS kategori,
    REGEXP_REPLACE(harga, '[^0-9]', '', 'g')::numeric AS harga
FROM raw_products;

-- C3. orders_clean
--     Hapus duplikat, ubah tipe data, seragamkan teks, buang baris tidak valid
DROP TABLE IF EXISTS orders_clean;
CREATE TABLE orders_clean AS
WITH dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_id) AS rn
    FROM raw_orders
),
typed AS (
    SELECT
        order_id,
        customer_id,
        product_id,
        tanggal_order::date                                   AS tanggal_order,
        qty,
        COALESCE(diskon_persen, 0)                            AS diskon_persen,
        LOWER(TRIM(status))                                   AS status,
        COALESCE(LOWER(TRIM(metode_bayar)), 'tidak diketahui') AS metode_bayar
    FROM dedup
    WHERE rn = 1
)
SELECT t.*
FROM typed t
WHERE t.qty IS NOT NULL
  AND t.qty > 0                                   -- buang qty kosong/nol/negatif
  AND t.tanggal_order <= CURRENT_DATE             -- buang tanggal masa depan
  AND EXISTS (SELECT 1                            -- buang customer yatim
              FROM customers_clean c
              WHERE c.customer_id = t.customer_id);

-- C4. fact_orders: gabungkan semua tabel + buat kolom turunan
DROP TABLE IF EXISTS fact_orders;
CREATE TABLE fact_orders AS
SELECT
    o.order_id,
    o.tanggal_order,
    DATE_TRUNC('month', o.tanggal_order)::date AS bulan,
    o.customer_id,
    c.kota,
    o.product_id,
    p.nama_produk,
    p.kategori,
    p.harga,
    o.qty,
    o.diskon_persen,
    ROUND(o.qty * p.harga * (1 - o.diskon_persen / 100.0), 0) AS total_harga,
    o.status,
    o.metode_bayar
FROM orders_clean o
JOIN customers_clean c ON c.customer_id = o.customer_id
JOIN products_clean  p ON p.product_id  = o.product_id;


-- =====================================================================
-- D. VALIDASI: pastikan hasil wrangling benar
-- =====================================================================

-- D1. Rekonsiliasi jumlah baris (dokumentasikan berapa yang dibuang)
SELECT
    (SELECT COUNT(*)                FROM raw_orders)      AS raw_baris,
    (SELECT COUNT(DISTINCT order_id) FROM raw_orders)     AS raw_order_unik,
    (SELECT COUNT(*)                FROM orders_clean)    AS orders_clean,
    (SELECT COUNT(*)                FROM fact_orders)     AS fact_orders;
-- Harapan: orders_clean = fact_orders (join tidak menghilangkan/melipatgandakan baris)
-- Selisih raw_order_unik - orders_clean = baris tidak valid yang dibuang.

-- D2. Tidak boleh ada duplikat lagi
SELECT COUNT(*) - COUNT(DISTINCT order_id) AS duplikat_tersisa
FROM fact_orders;

-- D3. Tidak boleh ada NULL di kolom penting
SELECT
    COUNT(*) FILTER (WHERE kota     IS NULL) AS kota_null,
    COUNT(*) FILTER (WHERE kategori IS NULL) AS kategori_null,
    COUNT(*) FILTER (WHERE qty      IS NULL) AS qty_null
FROM fact_orders;

-- D4. Nilai kategori sekarang seragam?
SELECT kategori, COUNT(*) FROM fact_orders GROUP BY kategori ORDER BY 1;
SELECT kota,     COUNT(*) FROM fact_orders GROUP BY kota     ORDER BY 1;
SELECT status,   COUNT(*) FROM fact_orders GROUP BY status   ORDER BY 1;


-- =====================================================================
-- E. EDA: pahami data & cari pola
--    Untuk analisis penjualan, order berstatus 'batal' dikecualikan.
-- =====================================================================

-- E1. Statistik deskriptif
SELECT
    COUNT(*)                                            AS n,
    ROUND(AVG(qty), 2)                                  AS rata_qty,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qty)    AS median_qty,
    MIN(qty)                                            AS min_qty,
    MAX(qty)                                            AS max_qty,
    ROUND(STDDEV(qty), 2)                               AS stddev_qty
FROM fact_orders;

SELECT
    ROUND(AVG(total_harga))                                     AS rata_total,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_harga)    AS median_total,
    MIN(total_harga)                                            AS min_total,
    MAX(total_harga)                                            AS max_total
FROM fact_orders;
-- Perhatikan: rata-rata qty jauh di atas median? Itu tanda outlier.

-- E2. Distribusi kategori: status order & qty
SELECT
    status,
    COUNT(*) AS jumlah,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS persen
FROM fact_orders
GROUP BY status
ORDER BY jumlah DESC;

SELECT qty, COUNT(*) AS jumlah_order
FROM fact_orders
GROUP BY qty
ORDER BY qty;

-- E3. Deteksi outlier dengan metode IQR
WITH q AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY qty) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qty) AS q3
    FROM fact_orders
)
SELECT f.order_id, f.tanggal_order, f.nama_produk, f.qty, f.total_harga
FROM fact_orders f, q
WHERE f.qty > q.q3 + 1.5 * (q.q3 - q.q1)
ORDER BY f.qty DESC;

-- KEPUTUSAN: qty 500 untuk barang seperti laptop hampir pasti salah input.
-- Dalam pekerjaan nyata, KONFIRMASI dulu ke tim terkait sebelum membuang.
-- Di latihan ini kita anggap salah input dan buang dari fact_orders.
DELETE FROM fact_orders WHERE qty > 100;

-- E4. Bivariate: kategori vs revenue
SELECT
    kategori,
    COUNT(*)          AS jml_order,
    SUM(qty)          AS total_qty,
    SUM(total_harga)  AS revenue,
    ROUND(100.0 * SUM(total_harga) / SUM(SUM(total_harga)) OVER (), 2) AS persen_revenue
FROM fact_orders
WHERE status <> 'batal'
GROUP BY kategori
ORDER BY revenue DESC;

-- E5. Kota vs revenue
SELECT
    kota,
    COUNT(*)          AS jml_order,
    SUM(total_harga)  AS revenue,
    ROUND(AVG(total_harga)) AS rata_nilai_order
FROM fact_orders
WHERE status <> 'batal'
GROUP BY kota
ORDER BY revenue DESC;

-- E6. Metode bayar
SELECT
    metode_bayar,
    COUNT(*) AS jml_order,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS persen
FROM fact_orders
WHERE status <> 'batal'
GROUP BY metode_bayar
ORDER BY jml_order DESC;

-- E7. Apakah diskon mendorong pembelian lebih banyak?
SELECT
    diskon_persen,
    COUNT(*)            AS jml_order,
    ROUND(AVG(qty), 2)  AS rata_qty
FROM fact_orders
WHERE status <> 'batal'
GROUP BY diskon_persen
ORDER BY diskon_persen;

-- E8. Tren bulanan + pertumbuhan month-over-month (MoM)
WITH bulanan AS (
    SELECT bulan, COUNT(*) AS jml_order, SUM(total_harga) AS revenue
    FROM fact_orders
    WHERE status <> 'batal'
    GROUP BY bulan
)
SELECT
    bulan,
    jml_order,
    revenue,
    LAG(revenue) OVER (ORDER BY bulan) AS revenue_bulan_lalu,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY bulan))
          / NULLIF(LAG(revenue) OVER (ORDER BY bulan), 0), 1) AS mom_persen
FROM bulanan
ORDER BY bulan;

-- E9. Segmentasi: revenue per kategori per bulan (pivot dengan FILTER)
SELECT
    bulan,
    SUM(total_harga) FILTER (WHERE kategori = 'Elektronik')   AS elektronik,
    SUM(total_harga) FILTER (WHERE kategori = 'Fashion')      AS fashion,
    SUM(total_harga) FILTER (WHERE kategori = 'Rumah Tangga') AS rumah_tangga,
    SUM(total_harga) FILTER (WHERE kategori = 'Kecantikan')   AS kecantikan
FROM fact_orders
WHERE status <> 'batal'
GROUP BY bulan
ORDER BY bulan;

-- E10. Bandingkan semester 1 vs semester 2 per kategori
--      Di sini biasanya terlihat DI MANA penurunan terjadi.
SELECT
    kategori,
    CASE WHEN tanggal_order < DATE '2025-07-01'
         THEN 'H1 (Jan-Jun)' ELSE 'H2 (Jul-Des)' END AS periode,
    COUNT(*)          AS jml_order,
    SUM(total_harga)  AS revenue
FROM fact_orders
WHERE status <> 'batal'
GROUP BY kategori, periode
ORDER BY kategori, periode;

-- E11. Tingkat pembatalan per kategori
SELECT
    kategori,
    COUNT(*) AS total_order,
    COUNT(*) FILTER (WHERE status = 'batal') AS batal,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'batal') / COUNT(*), 2) AS persen_batal
FROM fact_orders
GROUP BY kategori
ORDER BY persen_batal DESC;

-- E12. Top 10 pelanggan berdasarkan revenue (window function)
SELECT *
FROM (
    SELECT
        customer_id,
        kota,
        COUNT(*)          AS jml_order,
        SUM(total_harga)  AS revenue,
        RANK() OVER (ORDER BY SUM(total_harga) DESC) AS peringkat
    FROM fact_orders
    WHERE status <> 'batal'
    GROUP BY customer_id, kota
) t
WHERE peringkat <= 10
ORDER BY peringkat;

-- ---------------------------------------------------------------------
-- HIPOTESIS dari hasil EDA (tulis dengan kata-kata Anda sendiri):
--   "Revenue turun sejak Juli terutama karena jumlah order kategori
--    Elektronik anjlok, sementara kategori lain relatif stabil."
--
-- Langkah lanjutan yang masuk akal:
--   - Cek apakah penurunan merata di semua kota atau hanya sebagian
--   - Tanyakan ke tim: ada masalah stok, harga, atau kompetitor baru?
--   - Ingat: korelasi belum tentu sebab-akibat
-- ---------------------------------------------------------------------


-- =====================================================================
-- F. LATIHAN MANDIRI
-- =====================================================================
-- 1. Berapa persen order yang dibuang saat cleaning, dan karena alasan apa saja?
-- 2. Kota mana yang paling banyak mengalami penurunan revenue Elektronik
--    dari H1 ke H2?
-- 3. Berapa rata-rata jarak hari antara tanggal daftar pelanggan dan order
--    pertamanya? (petunjuk: JOIN customers_clean, MIN(tanggal_order))
-- 4. Hitung revenue per hari dalam seminggu (DOW). Hari apa paling ramai?
-- 5. Buat kolom segmen nilai order: 'Kecil' (< 500 rb), 'Sedang' (500 rb - 5 jt),
--    'Besar' (> 5 jt) dengan CASE WHEN, lalu hitung jumlah order tiap segmen.
-- 6. Pelanggan mana yang mendaftar tetapi tidak pernah order? (LEFT JOIN)
-- 7. Hitung rata-rata revenue 3 bulan bergerak (moving average) dengan
--    window frame ROWS BETWEEN 2 PRECEDING AND CURRENT ROW.
