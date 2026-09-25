# Latihan SQL — Dataset Chinook (Toko Musik Digital)

**Sumber dataset:** https://github.com/lerocha/chinook-database (cari file `Chinook_PostgreSql.sql`)

> **Catatan penting saat import ke pgAdmin:** file asli mengandung perintah `DROP DATABASE`, `CREATE DATABASE`, dan `\c chinook;` di bagian awal yang tidak kompatibel dengan GUI. Hapus semua baris tersebut (dari awal file sampai sebelum bagian `/* Create Tables */`) sebelum menjalankan script, karena database sudah dibuat manual sebelumnya.

## Ringkasan Schema
Tabel utama yang dipakai di latihan ini:
- `customer` — data pelanggan
- `invoice`, `invoice_line` — transaksi pembelian & rincian item
- `track`, `album`, `artist` — data lagu, album, dan musisi
- `genre` — genre musik
- `employee` — data karyawan/sales

---

## Soal 1 (Basic)
Tampilkan semua customer dari negara 'Brazil', urutkan berdasarkan kota.

```sql
SELECT first_name, last_name, city
FROM customer
WHERE country = 'Brazil'
ORDER BY city;
```

## Soal 2 (Basic-Intermediate)
Hitung jumlah track di setiap genre.

```sql
SELECT g.name AS genre, COUNT(t.track_id) AS jumlah_track
FROM genre g
JOIN track t ON g.genre_id = t.genre_id
GROUP BY g.name
ORDER BY jumlah_track DESC;
```

## Soal 3 (Intermediate)
Cari 10 customer dengan total pembelian (invoice) terbesar.

```sql
SELECT c.customer_id, c.first_name, c.last_name, SUM(i.total) AS total_belanja
FROM customer c
JOIN invoice i ON c.customer_id = i.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_belanja DESC
LIMIT 10;
```

## Soal 4 (Intermediate)
Album mana yang paling banyak dibeli (berdasarkan jumlah track terjual di invoice_line)?

```sql
SELECT al.title AS album, COUNT(il.invoice_line_id) AS jumlah_terjual
FROM album al
JOIN track t ON al.album_id = t.album_id
JOIN invoice_line il ON t.track_id = il.track_id
GROUP BY al.title
ORDER BY jumlah_terjual DESC
LIMIT 5;
```

## Soal 5 (Intermediate-Advanced)
Hitung total revenue per tahun.

```sql
SELECT 
  EXTRACT(YEAR FROM invoice_date) AS tahun,
  SUM(total) AS total_revenue
FROM invoice
GROUP BY tahun
ORDER BY tahun;
```

## Soal 6 (Advanced) — Window Function
Ranking artist berdasarkan total revenue yang dihasilkan dari penjualan track mereka.

```sql
SELECT 
  ar.name AS artist,
  SUM(il.unit_price * il.quantity) AS total_revenue,
  RANK() OVER (ORDER BY SUM(il.unit_price * il.quantity) DESC) AS ranking
FROM artist ar
JOIN album al ON ar.artist_id = al.artist_id
JOIN track t ON al.album_id = t.album_id
JOIN invoice_line il ON t.track_id = il.track_id
GROUP BY ar.name
ORDER BY ranking
LIMIT 10;
```

## Soal 7 (Advanced) — CTE + Window Function
Cari customer yang genre favoritnya (paling banyak dibeli) adalah 'Rock'.

```sql
WITH genre_per_customer AS (
  SELECT 
    c.customer_id, c.first_name, c.last_name,
    g.name AS genre,
    COUNT(*) AS jumlah_beli,
    RANK() OVER (PARTITION BY c.customer_id ORDER BY COUNT(*) DESC) AS rnk
  FROM customer c
  JOIN invoice i ON c.customer_id = i.customer_id
  JOIN invoice_line il ON i.invoice_id = il.invoice_id
  JOIN track t ON il.track_id = t.track_id
  JOIN genre g ON t.genre_id = g.genre_id
  GROUP BY c.customer_id, c.first_name, c.last_name, g.name
)
SELECT customer_id, first_name, last_name, genre, jumlah_beli
FROM genre_per_customer
WHERE rnk = 1 AND genre = 'Rock';
```

## Soal 8 (Advanced) — Running Total
Running total revenue bulanan sepanjang waktu.

```sql
SELECT 
  DATE_TRUNC('month', invoice_date) AS bulan,
  SUM(total) AS revenue_bulan,
  SUM(SUM(total)) OVER (ORDER BY DATE_TRUNC('month', invoice_date)) AS running_total
FROM invoice
GROUP BY bulan
ORDER BY bulan;
```
