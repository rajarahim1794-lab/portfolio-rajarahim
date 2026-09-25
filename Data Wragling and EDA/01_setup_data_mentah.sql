-- =====================================================================
-- 01_SETUP_DATA_MENTAH.SQL
-- Latihan Data Wrangling & EDA (PostgreSQL + DBeaver)
-- Studi kasus: e-commerce, tahun 2025
--
-- Script ini membuat 3 tabel MENTAH yang sengaja berantakan:
--   raw_customers, raw_products, raw_orders
--
-- Cara menjalankan di DBeaver:
--   1. Buka SQL Editor (Ctrl+])
--   2. Jalankan SELURUH script dengan Alt+X (Execute Script)
--   3. Script aman dijalankan ulang (schema lama akan dihapus)
--
-- Catatan: data dibuat dengan random() + setseed(), jadi angka pasti
-- Anda bisa sedikit berbeda dari contoh. Yang penting pola masalahnya sama.
-- =====================================================================

DROP SCHEMA IF EXISTS latihan CASCADE;
CREATE SCHEMA latihan;
SET search_path TO latihan;

SELECT setseed(0.42);  -- supaya hasil random konsisten dalam satu sesi

-- ---------------------------------------------------------------------
-- 1. STRUKTUR TABEL (sengaja banyak kolom bertipe TEXT, seperti data mentah)
-- ---------------------------------------------------------------------
CREATE TABLE raw_customers (
    customer_id    INT,
    nama           TEXT,
    kota           TEXT,
    tanggal_daftar TEXT,
    email          TEXT
);

CREATE TABLE raw_products (
    product_id  INT,
    nama_produk TEXT,
    kategori    TEXT,
    harga       TEXT
);

CREATE TABLE raw_orders (
    order_id       INT,
    customer_id    INT,
    product_id     INT,
    tanggal_order  TEXT,
    qty            INT,
    diskon_persen  NUMERIC,
    status         TEXT,
    metode_bayar   TEXT
);

-- ---------------------------------------------------------------------
-- 2. DATA PRODUK (10 produk, kategori & harga berantakan)
-- ---------------------------------------------------------------------
INSERT INTO raw_products VALUES
 (1,  'Laptop Ryzen',     'Elektronik',   '12500000'),
 (2,  'Smartphone X',     'elektronik ',  'Rp3500000'),
 (3,  'Earbuds Pro',      'ELEKTRONIK',   '450000'),
 (4,  'Kaos Polos',       'Fashion',      '75000'),
 (5,  'Jaket Hoodie',     'fashion',      '250000'),
 (6,  'Sepatu Sneakers',  'Fashion',      'Rp600000'),
 (7,  'Blender',          'Rumah Tangga', '350000'),
 (8,  'Rice Cooker',      'Rumah Tangga', '500000'),
 (9,  'Serum Wajah',      'Kecantikan',   '180000'),
 (10, 'Lipstik',          'Kecantikan',   '95000');

-- ---------------------------------------------------------------------
-- 3. DATA PELANGGAN (200 pelanggan)
--    Masalah: nama kota tidak konsisten, format tanggal campur, email kosong
-- ---------------------------------------------------------------------
INSERT INTO raw_customers
SELECT
    g,
    'Pelanggan ' || g,
    (ARRAY['Surabaya','surabaya','Jakarta','DKI Jakarta','Bandung',
           'Malang','Semarang','Medan','Jakarta ','Sby'])[1 + floor(random()*10)::int],
    CASE WHEN random() < 0.9
         THEN to_char(DATE '2023-01-01' + floor(random()*700)::int, 'YYYY-MM-DD')
         ELSE to_char(DATE '2023-01-01' + floor(random()*700)::int, 'DD/MM/YYYY')
    END,
    CASE WHEN random() < 0.1 THEN NULL
         ELSE 'pelanggan' || g || '@mail.com'
    END
FROM generate_series(1, 200) AS g;

-- Masalah: pelanggan tercatat dua kali (duplikat)
INSERT INTO raw_customers
SELECT * FROM raw_customers WHERE customer_id IN (7, 8, 9);

-- ---------------------------------------------------------------------
-- 4. DATA ORDER (3.000 order sepanjang 2025)
--    Pola tersembunyi: mulai 1 Juli 2025, order kategori Elektronik
--    (product_id 1-3) turun tajam. Ini yang nanti Anda temukan lewat EDA.
-- ---------------------------------------------------------------------
INSERT INTO raw_orders
SELECT
    o.order_id,
    1 + floor(random()*200)::int,
    CASE WHEN o.tgl >= DATE '2025-07-01' AND random() < 0.6
         THEN 4 + floor(random()*7)::int          -- produk non-elektronik
         ELSE 1 + floor(random()*10)::int
    END,
    to_char(o.tgl, 'YYYY-MM-DD'),
    1 + floor(random()*5)::int,
    (ARRAY[0,0,0,5,10,15,20,50])[1 + floor(random()*8)::int],
    (ARRAY['selesai','Selesai','SELESAI','batal','Batal','pending','dikirim'])
        [1 + floor(random()*7)::int],
    (ARRAY['transfer','ewallet','cod','kartu kredit', NULL])[1 + floor(random()*5)::int]
FROM (
    SELECT g AS order_id,
           DATE '2025-01-01' + floor(random()*365)::int AS tgl
    FROM generate_series(1, 3000) AS g
) AS o;

-- ---------------------------------------------------------------------
-- 5. SUNTIKKAN MASALAH DATA (seperti kondisi dunia nyata)
-- ---------------------------------------------------------------------
-- a) qty kosong
UPDATE raw_orders SET qty = NULL WHERE order_id % 97 = 0;

-- b) qty nol / negatif (tidak valid)
UPDATE raw_orders SET qty = -1 WHERE order_id IN (10, 20, 30);
UPDATE raw_orders SET qty = 0  WHERE order_id IN (40, 50);

-- c) qty ekstrem (outlier, kemungkinan salah input)
UPDATE raw_orders SET qty = 500 WHERE order_id IN (77, 1500);

-- d) tanggal di masa depan (tidak mungkin)
UPDATE raw_orders SET tanggal_order = '2030-01-01' WHERE order_id IN (100, 200, 300);

-- e) customer_id yang tidak ada di tabel pelanggan (orphan)
UPDATE raw_orders SET customer_id = 999 WHERE order_id IN (5, 15, 25);

-- f) order tercatat dua kali (duplikat persis)
INSERT INTO raw_orders
SELECT * FROM raw_orders WHERE order_id % 50 = 0;

-- ---------------------------------------------------------------------
-- 6. CEK CEPAT: data berhasil dibuat?
-- ---------------------------------------------------------------------
SELECT 'raw_customers' AS tabel, COUNT(*) AS jumlah_baris FROM raw_customers
UNION ALL
SELECT 'raw_products',  COUNT(*) FROM raw_products
UNION ALL
SELECT 'raw_orders',    COUNT(*) FROM raw_orders;
-- Harapan: raw_customers = 203, raw_products = 10, raw_orders = sekitar 3.060
