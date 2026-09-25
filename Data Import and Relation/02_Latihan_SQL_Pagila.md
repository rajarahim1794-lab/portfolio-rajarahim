# Latihan SQL — Dataset Pagila (DVD Rental Store)

**Sumber dataset:** https://github.com/devrimgunduz/pagila (gunakan rilis `pagila-v4.0.0` untuk menghindari kebutuhan extension `pgvector`)

## Ringkasan Schema
Tabel utama yang dipakai di latihan ini:
- `customer` — data pelanggan
- `rental` — transaksi penyewaan film
- `payment` — pembayaran
- `film`, `film_category`, `category` — data film & genre
- `film_actor`, `actor` — aktor per film
- `store`, `staff` — data toko & karyawan
- `inventory` — stok film per toko

---

## Soal 1 (Basic) — Filter & Sort
Tampilkan nama depan dan belakang customer yang tinggal di suatu negara tertentu, urutkan berdasarkan nama depan.

```sql
SELECT c.first_name, c.last_name
FROM customer c
JOIN address a ON c.address_id = a.address_id
JOIN city ci ON a.city_id = ci.city_id
JOIN country co ON ci.country_id = co.country_id
WHERE co.country = 'Australia'
ORDER BY c.first_name;
```

## Soal 2 (Basic-Intermediate) — Agregasi + Join
Hitung jumlah film per kategori genre.

```sql
SELECT cat.name AS kategori, COUNT(fc.film_id) AS jumlah_film
FROM category cat
JOIN film_category fc ON cat.category_id = fc.category_id
GROUP BY cat.name
ORDER BY jumlah_film DESC;
```

## Soal 3 (Intermediate) — Top N Customer
Cari 10 customer dengan total pembayaran (payment) terbesar.

```sql
SELECT c.customer_id, c.first_name, c.last_name, SUM(p.amount) AS total_bayar
FROM customer c
JOIN payment p ON c.customer_id = p.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_bayar DESC
LIMIT 10;
```

## Soal 4 (Intermediate) — CASE WHEN
Kelompokkan film berdasarkan durasi: 'Pendek' (<60 menit), 'Sedang' (60-120 menit), 'Panjang' (>120 menit), lalu hitung jumlahnya.

```sql
SELECT 
  CASE 
    WHEN length < 60 THEN 'Pendek'
    WHEN length BETWEEN 60 AND 120 THEN 'Sedang'
    ELSE 'Panjang'
  END AS kategori_durasi,
  COUNT(*) AS jumlah
FROM film
GROUP BY kategori_durasi;
```

## Soal 5 (Intermediate) — LEFT JOIN untuk cari yang "tidak ada"
Film mana saja yang tidak pernah disewa sama sekali?

```sql
SELECT f.film_id, f.title
FROM film f
LEFT JOIN inventory i ON f.film_id = i.film_id
LEFT JOIN rental r ON i.inventory_id = r.inventory_id
WHERE r.rental_id IS NULL;
```

## Soal 6 (Intermediate-Advanced) — Date Functions
Hitung total revenue per bulan per toko.

```sql
SELECT 
  s.store_id,
  DATE_TRUNC('month', p.payment_date) AS bulan,
  SUM(p.amount) AS total_revenue
FROM payment p
JOIN staff st ON p.staff_id = st.staff_id
JOIN store s ON st.store_id = s.store_id
GROUP BY s.store_id, bulan
ORDER BY s.store_id, bulan;
```

## Soal 7 (Advanced) — Window Function RANK
Ranking customer berdasarkan total pembayaran di masing-masing toko (bukan ranking global).

```sql
SELECT 
  s.store_id,
  c.customer_id,
  c.first_name,
  SUM(p.amount) AS total_bayar,
  RANK() OVER (PARTITION BY s.store_id ORDER BY SUM(p.amount) DESC) AS ranking
FROM customer c
JOIN payment p ON c.customer_id = p.customer_id
JOIN store s ON c.store_id = s.store_id
GROUP BY s.store_id, c.customer_id, c.first_name;
```

## Soal 8 (Advanced) — Churn Analysis
Cari customer yang aktif (pernah rental) tapi tidak melakukan rental lagi dalam 90 hari terakhir dari tanggal transaksi terakhir di database.

```sql
WITH last_date AS (
  SELECT MAX(rental_date) AS max_date FROM rental
)
SELECT c.customer_id, c.first_name, c.last_name, MAX(r.rental_date) AS rental_terakhir
FROM customer c
JOIN rental r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING MAX(r.rental_date) < (SELECT max_date FROM last_date) - INTERVAL '90 days';
```

> **Catatan:** Gunakan referensi tanggal transaksi terakhir di database (`MAX(rental_date)`), BUKAN `CURRENT_DATE`, karena dataset ini historis/statis dan tanggalnya sudah lama — kalau pakai `CURRENT_DATE`, semua data akan dianggap "churn".

## Soal 9 (Advanced) — Running Total
Tampilkan running total (kumulatif) revenue bulanan sepanjang waktu.

```sql
SELECT 
  DATE_TRUNC('month', payment_date) AS bulan,
  SUM(amount) AS revenue_bulan,
  SUM(SUM(amount)) OVER (ORDER BY DATE_TRUNC('month', payment_date)) AS running_total
FROM payment
GROUP BY bulan
ORDER BY bulan;
```

## Soal 10 (Advanced) — CTE + Window Function Gabungan
Cari aktor paling populer (paling banyak muncul di film yang disewa) di setiap kategori genre.

```sql
WITH rental_per_actor_category AS (
  SELECT 
    cat.name AS kategori,
    a.actor_id,
    a.first_name,
    a.last_name,
    COUNT(r.rental_id) AS jumlah_disewa,
    RANK() OVER (PARTITION BY cat.name ORDER BY COUNT(r.rental_id) DESC) AS rnk
  FROM rental r
  JOIN inventory i ON r.inventory_id = i.inventory_id
  JOIN film f ON i.film_id = f.film_id
  JOIN film_category fc ON f.film_id = fc.film_id
  JOIN category cat ON fc.category_id = cat.category_id
  JOIN film_actor fa ON f.film_id = fa.film_id
  JOIN actor a ON fa.actor_id = a.actor_id
  GROUP BY cat.name, a.actor_id, a.first_name, a.last_name
)
SELECT kategori, first_name, last_name, jumlah_disewa
FROM rental_per_actor_category
WHERE rnk = 1
ORDER BY kategori;
```
