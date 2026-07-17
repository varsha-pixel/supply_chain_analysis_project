# Supply Chain & Inventory Analysis

**Problem statement**

An operations team wants to know: which shipping modes are actually reliable (not just premium-labeled), where late deliveries cluster geographically, which products carry the highest replenishment burden, which fulfillment markets perform best, and which customers are most valuable by recency/frequency/spend.

**Dataset**

**Kaggle**: DataCo Smart Supply Chain 

**Domain**: operations, logistics & supply chain analytics

**Size**: 180,519 orders, 53 columns (44 loaded — see note below)

**Data-handling note**: the dataset ships fabricated-but-PII-shaped customer fields (email, name, password, street address). db.py drops them at load time — worth doing as a habit even on a synthetic teaching dataset.

**Tools & Technologies**

**SQL Server** – Data querying and analysis

**Power BI** – Dashboard development

**Python (Pandas)** – Data cleaning and preprocessing

**Jupyter Notebook** – Data preparation

**Analysis walkthrough & key findings**

**Shipping-mode label ≠ reliability** — "First Class" has the highest late-delivery rate (95.3%), not the lowest; "Same Day" is the most reliable (45.7% late) and "Standard Class" the most punctual overall (38.1% late). The label appears to describe a paid service tier with a tight scheduled window, not the carrier's actual on-time performance — a reminder to verify labels against outcomes rather than assume "premium = better."

**Reorder risk** — approximated via a replenishment-burden score (avg order quantity x avg lead time) ranked into quartiles, since the dataset has no real stock column.
Fulfillment markets — on-time rate and average profit ratio are broadly similar across markets (~45% on-time, ~0.12 profit ratio), suggesting the late-delivery problem is systemic (shipping-mode/process related) rather than concentrated in one region's fulfillment operation.

**RFM segmentation** — "Loyal" and "Champions" customers, a minority by headcount, hold the majority of total revenue — a clear prioritization signal for a retention campaign.
