CREATE DATABASE Customers_transactions;
UPDATE customers SET Gender = NULL WHERE Gender ='';
SET SQL_SAFE_UPDATES = 0;
UPDATE customers SET Age = NULL WHERE Age ='';
ALTER TABLE customers MODIFY Age INT NULL;

SELECT * FROM customers;

CREATE TABLE Transactions
(date_new DATE,
Id_check INT,
ID_client INT,
Count_products DECIMAL (10,3),
Sum_payment DECIMAL (10,2));

LOAD DATA INFILE "C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\TRANSACTIONS_final.csv"
INTO TABLE Transactions
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


SHOW VARIABLES LIKE 'secure_file_priv';

#Используя данные таблиц customer_info.xlsx (информация о клиентах) и transactions_info.xlsx 
#(информация о транзакциях за период с 01.06.2015 по 01.06.2016), нужно вывести:
#1.список клиентов с непрерывной историей за год, то есть каждый месяц на регулярной основе без пропусков за указанный годовой период, 
#средний чек за период с 01.06.2015 по 01.06.2016, средняя сумма покупок за месяц, количество всех операций по клиенту за период;

WITH monthly_activity AS (
    SELECT
        t.Id_client,
        YEAR(t.date_new) AS yr,
        MONTH(t.date_new) AS mn,
        SUM(t.Sum_payment) AS month_sum,
        COUNT(t.Id_check) AS month_ops
    FROM transactions t
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
    GROUP BY t.Id_client, YEAR(t.date_new), MONTH(t.date_new)
),

clients_full_year AS (
    SELECT
        Id_client
    FROM monthly_activity
    GROUP BY Id_client
    HAVING COUNT(DISTINCT CONCAT(yr, '-', mn)) = 12
)

SELECT
    c.Id_client,
    AVG(t.Sum_payment) AS avg_check,
    SUM(t.Sum_payment) / 12 AS avg_month_sum,
    COUNT(t.Id_check) AS total_operations
FROM clients_full_year fy
JOIN transactions t ON fy.Id_client = t.Id_client
JOIN customers c ON c.Id_client = fy.Id_client
WHERE t.date_new >= '2015-06-01'
  AND t.date_new <  '2016-06-01'
GROUP BY c.Id_client
ORDER BY c.Id_client;


#2.информацию в разрезе месяцев:
#средняя сумма чека в месяц;
#среднее количество операций в месяц;
#среднее количество клиентов, которые совершали операции;
#долю от общего количества операций за год и долю в месяц от общей суммы операций;
#вывести % соотношение M/F/NA в каждом месяце с их долей затрат;

WITH base AS (
    SELECT
        DATE_FORMAT(t.date_new, '%Y-%m') AS ym,
        t.Id_client,
        IFNULL(c.Gender, 'NA') AS Gender,
        t.Id_check,
        t.Sum_payment
    FROM transactions t
    JOIN customers c ON c.Id_client = t.Id_client
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
),

year_totals AS (
    SELECT
        COUNT(Id_check) AS total_ops_year,
        SUM(Sum_payment) AS total_sum_year
    FROM base
),

month_metrics AS (
    SELECT
        ym,
        AVG(Sum_payment) AS avg_check_month,
        COUNT(Id_check) AS ops_month,
        COUNT(DISTINCT Id_client) AS clients_month,
        COUNT(Id_check) * 1.0 / COUNT(DISTINCT Id_client) AS avg_ops_per_client,
        SUM(Sum_payment) AS sum_month
    FROM base
    GROUP BY ym
),

gender_metrics AS (
    SELECT
        ym,
        Gender,
        COUNT(DISTINCT Id_client) AS gender_clients,
        SUM(Sum_payment) AS gender_sum
    FROM base
    GROUP BY ym, Gender
)

SELECT
    m.ym,
    ROUND(m.avg_check_month, 2) AS avg_check_month,
    ROUND(m.avg_ops_per_client, 2) AS avg_ops_per_client,
    m.clients_month,

    ROUND(m.ops_month * 1.0 / y.total_ops_year, 4) AS ops_share_year,
    ROUND(m.sum_month * 1.0 / y.total_sum_year, 4) AS sum_share_year,

    ROUND(SUM(CASE WHEN g.Gender = 'M'  THEN g.gender_clients ELSE 0 END)
          * 100.0 / m.clients_month, 2) AS pct_clients_m,

    ROUND(SUM(CASE WHEN g.Gender = 'F'  THEN g.gender_clients ELSE 0 END)
          * 100.0 / m.clients_month, 2) AS pct_clients_f,

    ROUND(SUM(CASE WHEN g.Gender = 'NA' THEN g.gender_clients ELSE 0 END)
          * 100.0 / m.clients_month, 2) AS pct_clients_na,

    ROUND(SUM(CASE WHEN g.Gender = 'M'  THEN g.gender_sum ELSE 0 END)
          * 100.0 / m.sum_month, 2) AS pct_sum_m,

    ROUND(SUM(CASE WHEN g.Gender = 'F'  THEN g.gender_sum ELSE 0 END)
          * 100.0 / m.sum_month, 2) AS pct_sum_f,

    ROUND(SUM(CASE WHEN g.Gender = 'NA' THEN g.gender_sum ELSE 0 END)
          * 100.0 / m.sum_month, 2) AS pct_sum_na

FROM month_metrics m
JOIN gender_metrics g ON m.ym = g.ym
CROSS JOIN year_totals y

GROUP BY
    m.ym,
    m.avg_check_month,
    m.avg_ops_per_client,
    m.clients_month,
    m.ops_month,
    m.sum_month,
    y.total_ops_year,
    y.total_sum_year

ORDER BY m.ym;


#3.возрастные группы клиентов с шагом 10 лет и отдельно клиентов, у которых нет данной информации, с параметрами сумма и количество 
#операций за весь период, и поквартально - средние показатели и %.

WITH base AS (
    SELECT
        t.Id_check,
        t.Id_client,
        t.Sum_payment,
        t.date_new,

        CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS yq,
        c.Age
    FROM transactions t
    JOIN customers c ON c.Id_client = t.Id_client
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new <  '2016-06-01'
),

age_groups AS (
    SELECT
        *,
        CASE
            WHEN Age IS NULL THEN 'NA'
            WHEN Age < 0 THEN 'NA'
            ELSE CONCAT(FLOOR(Age / 10) * 10, '-', FLOOR(Age / 10) * 10 + 9)
        END AS age_group
    FROM base
),

period_totals AS (
    SELECT
        age_group,
        COUNT(Id_check) AS ops_total,
        SUM(Sum_payment) AS sum_total
    FROM age_groups
    GROUP BY age_group
),

quarter_metrics AS (
    SELECT
        yq,
        age_group,
        COUNT(Id_check) AS ops_q,
        AVG(Sum_payment) AS avg_check_q,
        COUNT(Id_check) * 1.0 / COUNT(DISTINCT Id_client) AS avg_ops_per_client_q,
        SUM(Sum_payment) AS sum_q
    FROM age_groups
    GROUP BY yq, age_group
),

quarter_totals AS (
    SELECT
        yq,
        COUNT(Id_check) AS ops_q_total,
        SUM(Sum_payment) AS sum_q_total
    FROM age_groups
    GROUP BY yq
)

SELECT
    q.yq,
    q.age_group,
    ROUND(q.avg_check_q, 2) AS avg_check_q,
    ROUND(q.avg_ops_per_client_q, 2) AS avg_ops_per_client_q,
    ROUND(q.ops_q * 100.0 / qt.ops_q_total, 2) AS ops_share_q_pct,
    ROUND(q.sum_q * 100.0 / qt.sum_q_total, 2) AS sum_share_q_pct,
    p.ops_total,
    ROUND(p.sum_total, 2) AS sum_total
FROM quarter_metrics q
JOIN quarter_totals qt ON q.yq = qt.yq
JOIN period_totals p ON q.age_group = p.age_group
ORDER BY q.yq, q.age_group;
