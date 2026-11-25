-- =====================================================================
-- CareLoop Clinics – No-Show Guard
-- Part 2 — SQL: verify the numbers and find where no-shows cluster
-- Target: MySQL 8 (MySQL Workbench).
-- SQLiteOnline: skip the CREATE DATABASE / USE lines; everything else runs as is.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Task 2.1 — Build and load the database
-- ---------------------------------------------------------------------
CREATE DATABASE noshowguard;
USE noshowguard;

CREATE TABLE clinics (
  clinic_id VARCHAR(5) PRIMARY KEY, clinic_name VARCHAR(40) NOT NULL, city VARCHAR(20) NOT NULL,
  tier VARCHAR(10), latitude DECIMAL(8,4), longitude DECIMAL(8,4), temp_c DECIMAL(5,1));

CREATE TABLE appointments (
  appointment_id VARCHAR(8) PRIMARY KEY, patient_id VARCHAR(8) NOT NULL, clinic_id VARCHAR(5) NOT NULL,
  booked_on DATE, appt_date DATE, age INT, gender VARCHAR(1), distance_km DECIMAL(5,1), fee_inr INT,
  booking_channel VARCHAR(10), visit_type VARCHAR(12), reminder_sent VARCHAR(3), prior_no_shows INT,
  status VARCHAR(10), lead_days INT, no_show INT,
  FOREIGN KEY (clinic_id) REFERENCES clinics(clinic_id));

-- Now run load_data.sql (File > Open SQL Script > load_data.sql > Execute),
-- or: SOURCE load_data.sql;  (from the MySQL command line)

-- Verify the load
SELECT COUNT(*) AS clinics FROM clinics;
SELECT COUNT(*) AS appointments, SUM(no_show) AS no_shows FROM appointments;
-- Result: clinics = 8 | appointments = 990 | no_shows = 218 (same as Task 1.4)

-- Try to insert a second row with an existing primary key
INSERT INTO appointments VALUES ('A0001','P999','C01','2025-01-01','2025-01-05',30,'F',5.0,500,'App','Consultation','Yes',0,'Attended',4,0);
-- Error recorded (MySQL 8):
--   Error Code: 1062. Duplicate entry 'A0001' for key 'appointments.PRIMARY'
-- (SQLite wording: UNIQUE constraint failed: appointments.appointment_id)
-- The PRIMARY KEY rejects the duplicate, so the table still has 990 rows.


-- ---------------------------------------------------------------------
-- Task 2.2 — No-show rate by clinic
-- ---------------------------------------------------------------------
SELECT c.clinic_name,
       c.city,
       COUNT(*)                                     AS appointments,
       SUM(a.no_show)                               AS no_shows,
       ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1)  AS no_show_pct
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
GROUP BY c.clinic_id, c.clinic_name, c.city
HAVING COUNT(*) >= 95
ORDER BY no_show_pct DESC;
-- Result:
--   Hadapsar Care Centre     | Pune   | 143 | 39 | 27.3
--   Malviya Nagar Clinic     | Jaipur | 142 | 38 | 26.8
--   Kothrud Family Clinic    | Pune   | 160 | 36 | 22.5
--   Vijay Nagar Clinic       | Indore | 101 | 21 | 20.8
--   Edappally Medical Centre | Kochi  | 142 | 23 | 16.2
--   Vaishali Nagar Clinic    | Jaipur | 130 | 18 | 13.8

-- Same query without HAVING (all 8 clinics)
SELECT c.clinic_name,
       c.city,
       COUNT(*)                                     AS appointments,
       SUM(a.no_show)                               AS no_shows,
       ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1)  AS no_show_pct
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
GROUP BY c.clinic_id, c.clinic_name, c.city
ORDER BY no_show_pct DESC;
-- Result: two more clinics appear.
--   Gomti Nagar Care Point (Lucknow) has the HIGHEST rate of all eight, 33.3%,
--   but only 90 appointments (30 no-shows) - a small sample, so the HAVING filter hides it.
--   Sitabuldi Health Point (Nagpur): 82 appointments, 13 no-shows, 15.9%.
-- Pandas cross-check (03_model.ipynb, first section): groupby("clinic_id") counts
-- and no-show sums match these SQL numbers exactly for all 8 clinics.


-- ---------------------------------------------------------------------
-- Task 2.3 — Does booking far ahead matter? (lead-time bands)
-- ---------------------------------------------------------------------
SELECT CASE
         WHEN lead_days <= 7  THEN '1-7'
         WHEN lead_days <= 14 THEN '8-14'
         WHEN lead_days <= 30 THEN '15-30'
         ELSE '31+'
       END                                        AS lead_band,
       COUNT(*)                                   AS appointments,
       SUM(no_show)                               AS no_shows,
       ROUND(100.0 * SUM(no_show) / COUNT(*), 1)  AS no_show_pct
FROM appointments
GROUP BY lead_band
ORDER BY MIN(lead_days);
-- Result:
--   1-7   | 390 | 63 | 16.2
--   8-14  | 304 | 53 | 17.4
--   15-30 | 253 | 76 | 30.0
--   31+   |  43 | 26 | 60.5
-- Bookings made more than 30 days ahead are missed at almost 4x the rate of short-notice bookings.


-- ---------------------------------------------------------------------
-- Task 2.4 — Month-by-month trend (CTE + LAG)
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT SUBSTR(appt_date, 1, 7)                    AS month,
         COUNT(*)                                   AS appointments,
         ROUND(100.0 * SUM(no_show) / COUNT(*), 1)  AS no_show_pct
  FROM appointments
  GROUP BY SUBSTR(appt_date, 1, 7)
)
SELECT month,
       appointments,
       no_show_pct,
       ROUND(no_show_pct - LAG(no_show_pct) OVER (ORDER BY month), 1) AS change_pp
FROM monthly
ORDER BY month;
-- Result (month | appointments | rate | change in percentage points):
--   2025-01 | 157 | 24.8 | NULL
--   2025-02 | 151 | 20.5 | -4.3
--   2025-03 | 142 | 20.4 | -0.1
--   2025-04 | 177 | 20.9 |  0.5
--   2025-05 | 198 | 23.7 |  2.8
--   2025-06 | 165 | 21.2 | -2.5
-- The rate moves within about 20-25% every month: no clear seasonal trend.


-- ---------------------------------------------------------------------
-- Task 2.5 — Rank clinics inside each city, compare with the overall rate
-- ---------------------------------------------------------------------
WITH clinic_rates AS (
  SELECT c.clinic_name                                AS clinic,
         c.city,
         ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1)  AS no_show_pct,
         100.0 * SUM(a.no_show) / COUNT(*)            AS exact_pct
  FROM appointments a
  JOIN clinics c ON a.clinic_id = c.clinic_id
  GROUP BY c.clinic_id, c.clinic_name, c.city
)
SELECT clinic,
       city,
       no_show_pct,
       RANK() OVER (PARTITION BY city ORDER BY no_show_pct DESC) AS rank_in_city,
       CASE
         WHEN exact_pct > (SELECT 100.0 * SUM(no_show) / COUNT(*) FROM appointments) THEN 'above'
         WHEN exact_pct < (SELECT 100.0 * SUM(no_show) / COUNT(*) FROM appointments) THEN 'below'
         ELSE 'equal'
       END AS vs_overall
FROM clinic_rates
ORDER BY city, rank_in_city;
-- Overall rate (scalar subquery): 22.02%
SELECT ROUND(100.0 * SUM(no_show) / COUNT(*), 2) AS overall_pct FROM appointments;
-- Result:
--   Vijay Nagar Clinic       | Indore  | 20.8 | 1 | below
--   Malviya Nagar Clinic     | Jaipur  | 26.8 | 1 | above
--   Vaishali Nagar Clinic    | Jaipur  | 13.8 | 2 | below
--   Edappally Medical Centre | Kochi   | 16.2 | 1 | below
--   Gomti Nagar Care Point   | Lucknow | 33.3 | 1 | above
--   Sitabuldi Health Point   | Nagpur  | 15.9 | 1 | below
--   Hadapsar Care Centre     | Pune    | 27.3 | 1 | above
--   Kothrud Family Clinic    | Pune    | 22.5 | 2 | above
-- The comparison uses the unrounded clinic rate, so a clinic is only 'equal'
-- if it matches the overall rate exactly.
