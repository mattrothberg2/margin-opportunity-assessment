# Margin Opportunity Assessment by [MarginArc](https://marginarc.com)

**Free, open-source Salesforce package that scans your historical deals and shows exactly how much margin your team is leaving on the table.**

## What It Does

- **Scans your deals** — Analyzes Closed Won and Closed Lost opportunities over the past 24 months (configurable)
- **Segments by cohort** — Groups deals by OEM, deal size, and customer tier to create apples-to-apples comparisons
- **Quantifies the gap** — Calculates the dollar amount of margin opportunity by comparing each deal against its cohort median

## What It Does NOT Do

- **No data leaves Salesforce** — All analysis runs inside your org via Apex. Zero external API calls.
- **No writes to your data** — MOA only reads Opportunity, Account, Product, and User records. It never modifies them.
- **No proprietary code** — Fully open source under Apache 2.0. Read every line before you install.

## Installation

### From GitHub Release

1. Download the latest release from the [Releases page](https://github.com/mattrothberg2/margin-opportunity-assessment/releases)
2. Deploy to your Salesforce org:
   ```bash
   sf project deploy start --source-dir force-app
   ```
3. Assign the **MOA User** permission set to users who need access
4. Navigate to the **Margin Opportunity Assessment** tab and click **Run Scan**

### From Source

```bash
git clone https://github.com/mattrothberg2/margin-opportunity-assessment.git
cd margin-opportunity-assessment
sf project deploy start --source-dir force-app --target-org your-org-alias
```

## How It Works

See [docs/how-it-works.md](docs/how-it-works.md) for the full methodology.

**TL;DR:** MOA groups your deals into cohorts (OEM x Deal Size x Customer Tier), computes the median margin for each cohort, then sums the gap between each below-median deal and the median. That's your margin opportunity.

## Configuration

MOA uses a Hierarchy Custom Setting (`MOA_Config__c`) with these defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| Scan Months | 24 | How many months of deal history to analyze |
| Min Cohort Size | 5 | Minimum deals required to form a valid cohort |

## Requirements

- Salesforce org with Opportunity data
- Opportunities must have margin data (via Amount, custom fields, or OpportunityLineItems)
- API version 62.0+

## Screenshots

### KPI Summary
![MOA Dashboard — KPI Summary](docs/moa-summary.png)

### Segment Breakdown
![MOA Dashboard — Segment Breakdown](docs/moa-segments.png)

### Rep Leaderboard
![MOA Dashboard — Rep Leaderboard](docs/moa-reps.png)

> Screenshots shown from a demo org. Your results will vary based on your deal history.

## License

Apache 2.0 — see [LICENSE](LICENSE)

## Contributing

Issues and PRs welcome. Please read the code of conduct before contributing.

---

**Built by [MarginArc](https://marginarc.com)** — AI-powered margin optimization for IT VARs.
