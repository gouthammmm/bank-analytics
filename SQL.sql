-- Bank Analytics: Lending Portfolio Review
-- Dialect: MySQL 8+
-- Load the Finance_1 and finance_2 worksheets into tables with those names
-- before running these read-only analysis queries.

USE excelr;

-- 0. Data checks: row counts, unique loan IDs, and join coverage.
SELECT 'finance_1' AS source_table, COUNT(*) AS row_count,
       COUNT(DISTINCT id) AS distinct_loan_ids
FROM finance_1
UNION ALL
SELECT 'finance_2', COUNT(*), COUNT(DISTINCT id)
FROM finance_2;

SELECT COUNT(*) AS finance_1_rows,
       SUM(f2.id IS NOT NULL) AS matched_rows,
       SUM(f2.id IS NULL) AS unmatched_rows
FROM finance_1 AS f1
LEFT JOIN finance_2 AS f2 ON f1.id = f2.id;

-- 1. Annual originations: count, total principal, and average loan size.
SELECT YEAR(issue_d) AS issue_year,
       COUNT(DISTINCT id) AS loan_count,
       SUM(loan_amnt) AS originated_principal,
       ROUND(AVG(loan_amnt), 2) AS average_loan_amount
FROM finance_1
WHERE issue_d IS NOT NULL
GROUP BY YEAR(issue_d)
ORDER BY issue_year;

-- 2. Portfolio status mix. Shares are by loan count and original principal.
WITH portfolio_totals AS (
    SELECT COUNT(*) AS total_loans, SUM(loan_amnt) AS total_principal
    FROM finance_1
)
SELECT f1.loan_status,
       COUNT(*) AS loan_count,
       SUM(f1.loan_amnt) AS originated_principal,
       ROUND(100.0 * COUNT(*) / NULLIF(MAX(t.total_loans), 0), 2) AS loan_share_pct,
       ROUND(100.0 * SUM(f1.loan_amnt) / NULLIF(MAX(t.total_principal), 0), 2) AS principal_share_pct
FROM finance_1 AS f1
CROSS JOIN portfolio_totals AS t
GROUP BY f1.loan_status
ORDER BY loan_count DESC;

-- 3. Observed charge-off/default rate by grade.
-- Denominator includes only resolved outcomes (paid, charged off, or defaulted).
WITH resolved AS (
    SELECT grade,
           CASE WHEN loan_status = 'Default' OR loan_status LIKE '%Fully Paid'
                     OR loan_status LIKE '%Charged Off'
                THEN 1 ELSE 0 END AS is_resolved,
           CASE WHEN loan_status = 'Default' OR loan_status LIKE '%Charged Off'
                THEN 1 ELSE 0 END AS is_adverse,
           loan_amnt
    FROM finance_1
)
SELECT grade,
       COUNT(CASE WHEN is_resolved = 1 THEN 1 END) AS resolved_loans,
       SUM(CASE WHEN is_resolved = 1 THEN loan_amnt ELSE 0 END) AS resolved_principal,
       COUNT(CASE WHEN is_adverse = 1 THEN 1 END) AS charged_off_or_defaulted_loans,
       ROUND(100.0 * SUM(is_adverse) / NULLIF(SUM(is_resolved), 0), 2) AS observed_adverse_rate_pct
FROM resolved
GROUP BY grade
ORDER BY grade;

-- 4. Observed outcome rate by term and grade, excluding unresolved statuses.
WITH resolved AS (
    SELECT term, grade,
           CASE WHEN loan_status = 'Default' OR loan_status LIKE '%Fully Paid'
                     OR loan_status LIKE '%Charged Off'
                THEN 1 ELSE 0 END AS is_resolved,
           CASE WHEN loan_status = 'Default' OR loan_status LIKE '%Charged Off'
                THEN 1 ELSE 0 END AS is_adverse
    FROM finance_1
)
SELECT term, grade,
       SUM(is_resolved) AS resolved_loans,
       ROUND(100.0 * SUM(is_adverse) / NULLIF(SUM(is_resolved), 0), 2) AS observed_adverse_rate_pct
FROM resolved
GROUP BY term, grade
HAVING SUM(is_resolved) > 0
ORDER BY term, grade;

-- 5. Grade/sub-grade revolving balance, with loan counts for context.
SELECT f1.grade, f1.sub_grade,
       COUNT(DISTINCT f1.id) AS loan_count,
       SUM(f2.revol_bal) AS total_revolving_balance,
       ROUND(AVG(f2.revol_bal), 2) AS average_revolving_balance
FROM finance_1 AS f1
JOIN finance_2 AS f2 ON f1.id = f2.id
GROUP BY f1.grade, f1.sub_grade
ORDER BY f1.grade, f1.sub_grade;

-- 6. State-level resolved-loan outcomes. Small cohorts are omitted for stability.
WITH resolved AS (
    SELECT addr_state,
           CASE WHEN loan_status = 'Default' OR loan_status LIKE '%Fully Paid'
                     OR loan_status LIKE '%Charged Off'
                THEN 1 ELSE 0 END AS is_resolved,
           CASE WHEN loan_status = 'Default' OR loan_status LIKE '%Charged Off'
                THEN 1 ELSE 0 END AS is_adverse,
           loan_amnt
    FROM finance_1
)
SELECT addr_state,
       SUM(is_resolved) AS resolved_loans,
       SUM(CASE WHEN is_resolved = 1 THEN loan_amnt ELSE 0 END) AS resolved_principal,
       ROUND(100.0 * SUM(is_adverse) / NULLIF(SUM(is_resolved), 0), 2) AS observed_adverse_rate_pct
FROM resolved
WHERE addr_state IS NOT NULL
GROUP BY addr_state
HAVING SUM(is_resolved) >= 100
ORDER BY observed_adverse_rate_pct DESC, resolved_loans DESC;

-- 7. Payment totals by verification status, normalized by loan count.
SELECT f1.verification_status,
       COUNT(DISTINCT f1.id) AS loan_count,
       SUM(f1.loan_amnt) AS originated_principal,
       SUM(f2.total_pymnt) AS recorded_total_payments,
       ROUND(AVG(f2.total_pymnt), 2) AS average_recorded_payment_per_loan
FROM finance_1 AS f1
JOIN finance_2 AS f2 ON f1.id = f2.id
GROUP BY f1.verification_status
ORDER BY loan_count DESC;

-- 8. Payment composition by outcome: principal, interest, late fees, recoveries.
SELECT f1.loan_status,
       COUNT(DISTINCT f1.id) AS loan_count,
       SUM(f2.total_rec_prncp) AS principal_received,
       SUM(f2.total_rec_int) AS interest_received,
       SUM(f2.total_rec_late_fee) AS late_fees_received,
       SUM(f2.recoveries) AS recoveries
FROM finance_1 AS f1
JOIN finance_2 AS f2 ON f1.id = f2.id
GROUP BY f1.loan_status
ORDER BY loan_count DESC;
