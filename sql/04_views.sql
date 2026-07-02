/* =============================================================================
   04_VIEWS.SQL
   Layer 4 of 4  |  Data access layer + analytical views

   Two kinds of views:

   1. PASS-THROUGH VIEWS (V_*)
      Exact 1:1 SELECTs over each dimension and fact table (columns named
      explicitly, never SELECT *). This insulates the warehouse from direct
      queries and shields downstream tools (Tableau) from physical changes to
      the underlying tables — the standard first layer of a data access layer.

   2. ANALYTICAL VIEWS
      Business-question-specific views that handle the grouping, filtering,
      and calculations the BI tool shouldn't. Each maps directly to a
      question the business asked (see README).
   ============================================================================= */

USE DATABASE RETAIL_DW;
USE SCHEMA PUBLIC;

/* =============================================================================
   PASS-THROUGH VIEWS  —  Dimensions
   ============================================================================= */

CREATE OR REPLACE VIEW V_DIM_CHANNEL AS
SELECT DimChannelID, ChannelID, ChannelName, ChannelCategoryID, ChannelCategory
FROM Dim_Channel;

CREATE OR REPLACE VIEW V_DIM_CUSTOMER AS
SELECT DimCustomerID, CustomerID, FirstName, LastName, FullName, Gender, EmailAddress, DimLocationID
FROM Dim_Customer;

CREATE OR REPLACE VIEW V_DIM_DATE AS
SELECT DimDateID, FullDate, DayNameOfWeek, DayNumberOfMonth, MonthName, MonthNumberOfYear, CalendarYear
FROM Dim_Date;

CREATE OR REPLACE VIEW V_DIM_LOCATION AS
SELECT DimLocationID, Country, StateProvince, City, PostalCode, Address, SourceSystem
FROM Dim_Location;

CREATE OR REPLACE VIEW V_DIM_PRODUCT AS
SELECT DimProductID, ProductID, ProductName, ProductTypeID, ProductType,
       ProductCategoryID, ProductCategory, Color, Style, UnitOfMeasureID,
       Weight, Price, Cost, WholesalePrice
FROM Dim_Product;

CREATE OR REPLACE VIEW V_DIM_RESELLER AS
SELECT DimResellerID, ResellerID, ResellerName, Contact, EmailAddress, DimLocationID
FROM Dim_Reseller;

CREATE OR REPLACE VIEW V_DIM_STORE AS
SELECT DimStoreID, StoreID, StoreNumber, StoreManager, DimLocationID
FROM Dim_Store;

/* =============================================================================
   PASS-THROUGH VIEWS  —  Facts
   ============================================================================= */

CREATE OR REPLACE VIEW V_FACT_PRODUCTSALES_TARGET AS
SELECT DimProductID, DimTargetDateID, ProductTargetSalesQuantity
FROM Fact_ProductSalesTarget;

CREATE OR REPLACE VIEW V_FACT_SRCSALES_TARGET AS
SELECT DimStoreID, DimResellerID, DimChannelID, DimTargetDateID, SalesTargetAmount
FROM Fact_SRCSalesTarget;

CREATE OR REPLACE VIEW V_FACT_SALES_ACTUAL AS
SELECT DimProductID, DimStoreID, DimResellerID, DimCustomerID, DimChannelID,
       DimSaleDateID, DimLocationID, SalesHeaderID, SalesDetailID,
       SaleAmount, SaleQuantity, SaleUnitPrice, SaleExtendedCost, SaleTotalProfit
FROM Fact_SalesActual;

/* =============================================================================
   ANALYTICAL VIEWS  —  one per business question
   ============================================================================= */

/* Q1 — Sales vs. target: are the focus stores hitting plan?
   Aggregates actual sales against target for the focus stores in 2014. */
CREATE OR REPLACE VIEW StoreSalesPerformance_2014 AS
SELECT
    ds.StoreNumber,
    dd.CalendarYear,
    SUM(fsa.SaleAmount)                              AS TotalSalesAmount,
    SUM(fst.SalesTargetAmount)                       AS TotalTargetAmount,
    SUM(fsa.SaleAmount) - SUM(fst.SalesTargetAmount) AS SalesVsTarget
FROM Fact_SalesActual fsa
JOIN Dim_Store ds        ON fsa.DimStoreID    = ds.DimStoreID
JOIN Dim_Date dd         ON fsa.DimSaleDateID = dd.DimDateID
JOIN Fact_SRCSalesTarget fst
    ON ds.DimStoreID = fst.DimStoreID
   AND dd.DimDateID  = fst.DimTargetDateID
WHERE ds.StoreNumber IN (5, 8)
  AND dd.CalendarYear = 2014
GROUP BY ds.StoreNumber, dd.CalendarYear;

/* Q2 — Bonus allocation: how much casualwear profit did each store drive?
   Basis for splitting the annual bonus pool proportionally. */
CREATE OR REPLACE VIEW StoreBonus_CasualSales AS
SELECT
    ds.StoreNumber,
    dd.CalendarYear,
    dp.ProductType,
    SUM(fsa.SaleAmount) AS CasualSalesAmount
FROM Fact_SalesActual fsa
JOIN Dim_Store ds   ON fsa.DimStoreID   = ds.DimStoreID
JOIN Dim_Date dd    ON fsa.DimSaleDateID = dd.DimDateID
JOIN Dim_Product dp ON fsa.DimProductID = dp.DimProductID
WHERE dp.ProductType IN ('Men''s Casual', 'Women''s Casual')
  AND dd.CalendarYear IN (2013, 2014)
GROUP BY ds.StoreNumber, dd.CalendarYear, dp.ProductType;

/* Q3 — Weekly demand shape: which days drive sales at each store?
   Informs staffing and promotion scheduling. */
CREATE OR REPLACE VIEW StoreSales_ByWeekday AS
SELECT
    ds.StoreNumber,
    dd.DayNameOfWeek,
    SUM(fsa.SaleAmount) AS TotalSales
FROM Fact_SalesActual fsa
JOIN Dim_Store ds ON fsa.DimStoreID   = ds.DimStoreID
JOIN Dim_Date dd  ON fsa.DimSaleDateID = dd.DimDateID
WHERE ds.StoreNumber IN (5, 8)
GROUP BY ds.StoreNumber, dd.DayNameOfWeek
ORDER BY ds.StoreNumber, dd.DayNameOfWeek;

/* Q4 — Store density: do multi-store states out-earn single-store states?
   Informs market-expansion strategy. */
CREATE OR REPLACE VIEW StorePerformance_ByStateDensity AS
WITH StoreStateCounts AS (
    SELECT
        dl.StateProvince,
        COUNT(DISTINCT ds.StoreNumber) AS StoreCount
    FROM Dim_Store ds
    JOIN Dim_Location dl ON ds.DimLocationID = dl.DimLocationID
    GROUP BY dl.StateProvince
),
SalesWithStateInfo AS (
    SELECT
        dl.StateProvince,
        ds.StoreNumber,
        SUM(fsa.SaleAmount) AS TotalSales
    FROM Fact_SalesActual fsa
    JOIN Dim_Store ds    ON fsa.DimStoreID    = ds.DimStoreID
    JOIN Dim_Location dl ON ds.DimLocationID  = dl.DimLocationID
    GROUP BY dl.StateProvince, ds.StoreNumber
)
SELECT
    s.StateProvince,
    sc.StoreCount,
    CASE WHEN sc.StoreCount > 1 THEN 'Multiple Stores' ELSE 'Single Store' END AS StateType,
    SUM(s.TotalSales)              AS TotalSalesInState,
    COUNT(DISTINCT s.StoreNumber)  AS NumStores
FROM SalesWithStateInfo s
JOIN StoreStateCounts sc ON s.StateProvince = sc.StateProvince
GROUP BY s.StateProvince, sc.StoreCount;
