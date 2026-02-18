# How Margin Opportunity Assessment Works

MOA uses basic descriptive statistics to analyze your historical deal data. There is no AI, no machine learning, and no proprietary algorithms — just straightforward cohort analysis that any analyst could replicate in a spreadsheet.

## Step 1: Data Collection

MOA queries your Salesforce org for Opportunities closed in the configured time window (default: 24 months). It pulls:

- **Opportunity**: Amount, StageName, CloseDate, Owner
- **Account**: Industry, AnnualRevenue, NumberOfEmployees
- **OpportunityLineItem**: UnitPrice, Quantity, TotalPrice
- **Product2**: Name, Family, ProductCode

All queries run inside Salesforce using standard SOQL. No data leaves your org.

## Step 2: Cohort Segmentation

Each deal is assigned to a cohort based on three dimensions:

### OEM / Product Family
Derived from the Product2.Family or Product2.Name on the deal's line items. Deals with multiple products use the primary (highest-value) line item.

### Deal Size Bucket
Based on the Opportunity Amount:
- **Small**: < $25,000
- **Mid-Market**: $25,000 - $100,000
- **Enterprise**: $100,000 - $500,000
- **Strategic**: > $500,000

### Customer Segment
Based on Account.AnnualRevenue:
- **SMB**: < $50M
- **Mid-Market**: $50M - $500M
- **Enterprise**: > $500M

This creates cohorts like "Cisco + Mid-Market Deal + Enterprise Customer" — groups where you'd expect similar margin profiles.

## Step 3: Cohort Statistics

For each cohort with enough deals (minimum cohort size, default: 5), MOA calculates:

- **Median margin** — the 50th percentile margin in the cohort (used as the benchmark because it's robust to outliers)
- **P25 / P75 margin** — the interquartile range, showing typical margin spread
- **Average margin** — arithmetic mean for reference
- **Win rate** — percentage of deals in the cohort that were Closed Won
- **Total revenue** — sum of all deal amounts in the cohort

## Step 4: Margin Opportunity Calculation

For every Closed Won deal where the margin was below the cohort median:

```
deal_gap = cohort_median_margin - deal_actual_margin
deal_opportunity = deal_amount * deal_gap
```

The total margin opportunity is the sum of all deal gaps across all cohorts. This represents the dollar amount that would have been captured if every below-median deal had achieved at least the median margin for its cohort.

The **achievable average margin** is what your overall average margin would be if every deal hit its cohort median. The **annual opportunity** is the total gap annualized.

## Step 5: Rep Analysis

MOA also computes per-rep statistics:

- **Average margin vs. team average** — how each rep compares to peers
- **Consistency** — standard deviation of margins (lower = more consistent)
- **Margin left on table** — sum of below-median gaps for that rep's deals

## Step 6: Win Rate by Margin Band

Deals are grouped into margin bands (e.g., 0-5%, 5-10%, 10-15%, etc.) and MOA calculates the win rate for each band. This reveals the margin-win rate tradeoff: are you giving away margin without actually winning more?

## Why Median, Not Mean?

The median is used as the benchmark because:
1. It's **robust to outliers** — a single unusually high or low margin deal doesn't skew the benchmark
2. It represents what's **actually achievable** — half your deals already exceed the median
3. It's a **conservative target** — we're not asking reps to hit the top quartile, just the middle

## What This Is NOT

- This is **not AI or machine learning**. It's descriptive statistics.
- This is **not a pricing recommendation**. It shows where gaps exist, not what to charge.
- This is **not a guarantee**. Market conditions, competitive dynamics, and deal specifics all matter.

MOA gives you visibility into margin patterns. What you do with that visibility is up to you.

---

*For AI-powered margin optimization that provides real-time deal-specific recommendations, see [MarginArc](https://marginarc.com).*
