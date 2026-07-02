# Data Dictionary

Star schema with selective snowflake extensions. Two fact tables capture actual
sales and planned targets separately (they arrive at different grains); a third
holds product-level quantity targets. Dimensions use IDENTITY surrogate keys,
retain natural keys for traceability, and each carries an unknown member (`-1`).

## Fact Tables

### Fact_SalesActual
- **Grain:** one row per sales line item (`SalesDetailID`)
- **Purpose:** records actual sales across every dimension
- **Key measures:** `SaleAmount`, `SaleQuantity`, `SaleUnitPrice`, `SaleExtendedCost`, `SaleTotalProfit`
- **Notes:** profit and unit price are computed at load time; every foreign key resolves to a valid dimension row or its unknown member.

### Fact_SRCSalesTarget
- **Grain:** one row per store/reseller/channel target per year
- **Purpose:** planned sales-dollar targets for store, reseller, and channel entities
- **Key measure:** `SalesTargetAmount`
- **Notes:** `TargetName` routes each target to the correct entity; annual targets are attached to Jan 1 of the year in `Dim_Date`.

### Fact_ProductSalesTarget
- **Grain:** one row per product per year
- **Purpose:** planned sales-quantity targets by product
- **Key measure:** `ProductTargetSalesQuantity`

## Dimension Tables

| Dimension | Grain | Purpose / Notes |
|---|---|---|
| Dim_Date | one row per date | Time grouping — day name, month, calendar year for temporal analysis |
| Dim_Store | one row per store | Store-level analysis; resolves to `Dim_Location` |
| Dim_Customer | one row per customer | Demographic breakdowns; resolves to `Dim_Location` |
| Dim_Reseller | one row per reseller | Differentiates B2B buyers; resolves to `Dim_Location` |
| Dim_Product | one row per product | Snowflakes into product type and category; holds price, cost, wholesale price |
| Dim_Channel | one row per channel | Sales medium; snowflakes into channel category (Direct vs. Indirect) |
| Dim_Location | one row per unique address | Conformed geography built by UNION-ing customer, store, and reseller addresses, tagged by source system |

## Key Design Decisions

- **Surrogate keys** (`IDENTITY(1,1)`) on every dimension for consistency and performance; **natural keys** retained for lineage back to source.
- **Unknown members** (`-1`) in every dimension, with `COALESCE`/`CASE` logic in the fact loads so no fact row ever holds a NULL foreign key — enforced referential integrity.
- **Separate fact tables for actuals vs. targets** to avoid a grain mismatch.
- **Daily-target attachment:** annual targets are joined to year-start (`Jan 1`). This is a deliberate simplification; a production build could allocate the annual figure across all days for finer pacing analysis.
- **Snowflaking** applied only where a genuine hierarchy exists (product → type → category; channel → category).
