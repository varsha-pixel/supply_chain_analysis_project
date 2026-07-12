-- Supply Chain & Inventory Analysis (DataCo dataset) — DuckDB queries
--
-- Convention: each query is a named block delimited by `-- name: <name>`.
-- db.py parses this file and exposes each block as `run_query("<name>")`,
-- so both analysis.ipynb and app.py call these exact same queries.
--
-- Table available: `orders` (loaded from data/DataCoSupplyChainDataset.csv,
-- with customer PII columns like email/password/name deliberately excluded
-- at load time in db.py — good practice even on a synthetic Kaggle dataset).
--
-- Note: this dataset has no on-hand-inventory / stock-level column, so the
-- "reorder alert" query approximates reorder risk with a demand x lead-time
-- "replenishment burden" score rather than comparing against real stock —
-- see the query comment below for the full reasoning.

-- name: late_shipment_by_mode
-- The doc's headline query: late-delivery rate and average delay by
-- shipping mode.

SELECT
    "shipping_mode" AS shipping_mode,
    COUNT(*) AS total_orders,
    SUM(CAST(CASE WHEN late_delivery_risk = 1 THEN 1 ELSE 0 END AS INT)) AS late_orders,
    ROUND(SUM(CASE WHEN late_delivery_risk = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS late_pct,
    ROUND(AVG(CAST("days_for_shipping_real" AS INT) -CAST( "days_for_shipment_scheduled" AS INT)), 2) AS avg_delay_days
FROM dbo.cleaned_supply_chain
GROUP BY shipping_mode
ORDER BY late_pct DESC;

-- name: late_shipment_by_region
-- Regional x shipping-mode late-delivery heatmap data.
SELECT
    "order_region" ,
    "shipping_mode" AS shipping_mode,
    COUNT(*) AS total_orders,
    ROUND(SUM(CASE WHEN Late_delivery_risk = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS late_pct
FROM dbo.cleaned_supply_chain
GROUP BY order_region,shipping_mode
HAVING COUNT(*) >= 50
ORDER BY late_pct DESC;

-- name: reorder_risk_by_product
-- This dataset doesn't include an on-hand stock column, so a literal
-- "(avg daily demand x lead time) > current stock" alert isn't computable.
-- Instead this approximates *reorder risk* with a replenishment-burden
-- score (avg order quantity x avg lead time in days) and ranks products
-- into risk quartiles with NTILE — the highest-burden quartile is the one
-- that would need the tightest reorder-point monitoring in a real system.
WITH product_demand AS (
    SELECT
        "product_name" AS product_name,
        "category_name" AS category_name,
        COUNT(*) AS order_count,
        ROUND(AVG("order_item_quantity"), 2) AS avg_order_quantity,
        ROUND(AVG("days_for_shipping_real"), 2) AS avg_lead_time_days,
        ROUND(AVG("order_item_quantity") * AVG("days_for_shipping_real"), 2) AS replenishment_burden
    FROM dbo.cleaned_supply_chain
    GROUP BY product_name,category_name
    HAVING COUNT(*) >= 30
)
SELECT TOP 25
    *,
    NTILE(4) OVER (ORDER BY replenishment_burden DESC) AS risk_quartile
FROM product_demand
ORDER BY replenishment_burden DESC

-- name: market_reliability
-- The dataset has no distinct "supplier" entity, so this uses Market
-- (DataCo's fulfillment region: LATAM, Europe, Pacific Asia, USCA, Africa)
-- as the stand-in "supplier" for a reliability-scoring exercise: on-time
-- rate, average profit margin, and order-volume consistency.
WITH market_orders AS (
    SELECT
        market AS market,
        "order_region" AS region,
        late_delivery_risk,
        "order_item_profit_ratio" AS profit_ratio
    FROM dbo.cleaned_supply_chain
)
SELECT
    market,
    COUNT(*) AS total_orders,
    ROUND(100.0 - SUM(CASE WHEN Late_delivery_risk = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS on_time_pct,
    ROUND(AVG(profit_ratio), 3) AS avg_profit_ratio,
    COUNT(DISTINCT region) AS regions_served
FROM market_orders
GROUP BY market
ORDER BY on_time_pct DESC;

-- name: rfm_analysis
-- Recency (days since last order), Frequency (distinct order dates),
-- Monetary (total spend) per customer, each scored into quartiles with
-- NTILE — quartile 4 is always "best" for that dimension (most recent,
-- most frequent, highest spend) so the three scores are directly
-- comparable and summable into a combined RFM score.
WITH customer_orders AS (
    SELECT
        order_customer_id AS customer_id,
        CAST(order_date AS DATE) AS order_date,
        order_item_total AS order_total
    FROM dbo.cleaned_supply_chain
),

max_date AS (
    SELECT MAX(order_date) AS max_order_date
    FROM customer_orders
),

customer_agg AS (
    SELECT
        customer_id,
        MAX(order_date) AS last_order_date,
        COUNT(DISTINCT order_date) AS frequency,
        ROUND(SUM(order_total), 2) AS monetary
    FROM customer_orders
    GROUP BY customer_id
),

scored AS (
    SELECT
        c.customer_id,
        DATEDIFF(DAY, c.last_order_date, m.max_order_date) AS recency_days,
        c.frequency,
        c.monetary,

        NTILE(4) OVER (
            ORDER BY DATEDIFF(DAY, c.last_order_date, m.max_order_date) DESC
        ) AS recency_score,

        NTILE(4) OVER (
            ORDER BY c.frequency ASC
        ) AS frequency_score,

        NTILE(4) OVER (
            ORDER BY c.monetary ASC
        ) AS monetary_score

    FROM customer_agg c
    CROSS JOIN max_date m
)

SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,

    recency_score + frequency_score + monetary_score AS rfm_score,

    CASE
        WHEN recency_score + frequency_score + monetary_score >= 10 THEN 'Champions'
        WHEN recency_score + frequency_score + monetary_score >= 7 THEN 'Loyal'
        WHEN recency_score + frequency_score + monetary_score >= 4 THEN 'At Risk'
        ELSE 'Lost'
    END AS segment

FROM scored
ORDER BY rfm_score DESC;

-- name: rfm_segment_summary
-- Rollup of the RFM segmentation above — how many customers per segment,
-- and how much revenue each segment represents.
WITH customer_orders AS
(
    SELECT
        order_customer_id AS customer_id,
        CAST(order_date AS DATE) AS order_date,
        order_item_total AS order_total
    FROM dbo.cleaned_supply_chain
),

max_date AS
(
    SELECT MAX(order_date) AS max_order_date
    FROM customer_orders
),

customer_agg AS
(
    SELECT
        customer_id,
        MAX(order_date) AS last_order_date,
        COUNT(DISTINCT order_date) AS frequency,
        ROUND(SUM(order_total), 2) AS monetary
    FROM customer_orders
    GROUP BY customer_id
),

scored AS
(
    SELECT
        c.customer_id,
        c.monetary,

        NTILE(4) OVER
        (
            ORDER BY DATEDIFF(DAY, c.last_order_date, m.max_order_date) DESC
        ) AS recency_score,

        NTILE(4) OVER
        (
            ORDER BY c.frequency ASC
        ) AS frequency_score,

        NTILE(4) OVER
        (
            ORDER BY c.monetary ASC
        ) AS monetary_score

    FROM customer_agg c
    CROSS JOIN max_date m
),

segmented AS
(
    SELECT
        *,
        CASE
            WHEN recency_score + frequency_score + monetary_score >= 10 THEN 'Champions'
            WHEN recency_score + frequency_score + monetary_score >= 7 THEN 'Loyal'
            WHEN recency_score + frequency_score + monetary_score >= 4 THEN 'At Risk'
            ELSE 'Lost'
        END AS segment
    FROM scored
)

SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(SUM(monetary),2) AS total_revenue,
    ROUND(AVG(monetary),2) AS avg_revenue_per_customer
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;

-- name: category_options
-- Powers the category dropdown filter in the Streamlit dashboard.
SELECT DISTINCT "category_name" AS category
FROM dbo.cleaned_supply_chain
ORDER BY category;

-- name: filtered_late_shipments
-- Parameterized query behind the dashboard's shipment explorer.
SELECT TOP 20
    order_id,
    category_name AS category,
    order_region AS region,
    shipping_mode,
    days_for_shipping_real AS days_actual,
    days_for_shipment_scheduled AS days_scheduled,
    Late_delivery_risk,
    Sales
FROM dbo.cleaned_supply_chain
WHERE Late_delivery_risk = 1
ORDER BY
    CAST(days_for_shipping_real AS INT)
    - CAST(days_for_shipment_scheduled AS INT) DESC;