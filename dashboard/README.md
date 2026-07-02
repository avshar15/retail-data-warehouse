# Dashboard

Interactive Tableau dashboard built on the warehouse's analytical views. It
answers the four business questions with a global year filter and click-to-filter
interactions across visuals.

**[View the interactive dashboard on Tableau Public →](https://public.tableau.com/app/profile/avantika.sharma5537/viz/IMT577_DW_Avantika_Sharma_Dashboard_Story/Dashboard1)**

> Tableau Public does not support a live Snowflake connection, so the analytical
> views were exported to CSV and loaded into Tableau Public. Because the views
> are stable, the experience is identical to a live connection.

![Full dashboard](dashboard_full.png)

## What the dashboard shows

Four coordinated views, one per business question:

- **Sales vs. Target (Stores 5 & 8, 2013-2014)** - actual sales against plan. Store 5 outpaced target in both years and held demand steady into 2014; Store 8 beat target in 2013 but fell short in 2014.
- **Profit Breakdown for Bonus Allocation** - casualwear profit by store and year, the basis for splitting the bonus pool proportionally to profit contribution.
- **Sales Trends by Day** - Store 5 peaks Friday-Saturday (weekend-driven), while Store 8 stays flat across the week (steady everyday demand). Different demand shapes call for different staffing and promotion calendars.
- **Multi vs. Single-Store State Comparison** - states with multiple stores generated \$40M+ more in annual sales than single-store states, suggesting clustering amplifies reach in strong markets.

The full written findings and recommendations are in the [main README](../README.md#findings--recommendations).
