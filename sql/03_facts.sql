/* =============================================================================
   03_FACTS.SQL
   Layer 3 of 4  |  Fact tables (actuals + targets)

   Purpose:
     Build the measurable events of the warehouse. Three fact tables are used
     because actual sales and target sales arrive at DIFFERENT GRAINS —
     forcing them into one table would create a grain mismatch. Separating
     them keeps each fact clean and additive.

       Fact_SalesActual        — one row per sales line item (transaction grain)
       Fact_SRCSalesTarget     — store/reseller/channel sales targets
       Fact_ProductSalesTarget — product-level sales-quantity targets

   Referential integrity:
     Every fact row resolves to a valid dimension surrogate key. Where a
     source value is missing, it maps to the dimension's unknown member (-1)
     via COALESCE / CASE logic, so NO fact row ever carries a NULL foreign key.

   Design note on targets:
     Source targets are ANNUAL. They are joined to Jan 1 of the matching year
     (MonthNumberOfYear = 1, DayNumberOfMonth = 1) to attach them to the date
     dimension. This is a modeling simplification — a production build could
     allocate the annual target across all days of the year for finer-grained
     pacing analysis.
   ============================================================================= */

USE DATABASE RETAIL_DW;
USE SCHEMA PUBLIC;

/* -----------------------------------------------------------------------------
   FACT_PRODUCTSALESTARGET  — product-level annual quantity targets
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Fact_ProductSalesTarget (
    DimProductID                INT NOT NULL,
    DimTargetDateID             INT NOT NULL,
    ProductTargetSalesQuantity  INT NOT NULL,
    CONSTRAINT FK_Product     FOREIGN KEY (DimProductID)    REFERENCES Dim_Product(DimProductID),
    CONSTRAINT FK_TargetDate  FOREIGN KEY (DimTargetDateID) REFERENCES Dim_Date(DimDateID)
);

INSERT INTO Fact_ProductSalesTarget (DimProductID, DimTargetDateID, ProductTargetSalesQuantity)
SELECT
    p.DimProductID,
    d.DimDateID,
    COALESCE(tp.SalesQuantityTarget, 0)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_TARGETDATAPRODUCT tp
JOIN Dim_Product p ON tp.ProductID = p.ProductID
JOIN Dim_Date d
    ON  tp.Year = d.CalendarYear
    AND d.MonthNumberOfYear = 1
    AND d.DayNumberOfMonth  = 1;

/* -----------------------------------------------------------------------------
   FACT_SRCSALESTARGET  — store / reseller / channel sales targets
   TargetName routes the target to the correct entity (store vs reseller).
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Fact_SRCSalesTarget (
    DimStoreID          INT,
    DimResellerID       INT,
    DimChannelID        INT,
    DimTargetDateID     INT NOT NULL,
    SalesTargetAmount   FLOAT NOT NULL,
    CONSTRAINT FK_SRC_Store      FOREIGN KEY (DimStoreID)      REFERENCES Dim_Store(DimStoreID),
    CONSTRAINT FK_SRC_Reseller   FOREIGN KEY (DimResellerID)   REFERENCES Dim_Reseller(DimResellerID),
    CONSTRAINT FK_SRC_Channel    FOREIGN KEY (DimChannelID)    REFERENCES Dim_Channel(DimChannelID),
    CONSTRAINT FK_SRC_TargetDate FOREIGN KEY (DimTargetDateID) REFERENCES Dim_Date(DimDateID)
);

INSERT INTO Fact_SRCSalesTarget (DimStoreID, DimResellerID, DimChannelID, DimTargetDateID, SalesTargetAmount)
SELECT
    CASE WHEN tdc.TargetName = 'Store'    THEN COALESCE(s.DimStoreID, -1)    ELSE -1 END,
    CASE WHEN tdc.TargetName = 'Reseller' THEN COALESCE(r.DimResellerID, -1) ELSE -1 END,
    COALESCE(c.DimChannelID, -1),
    d.DimDateID,
    COALESCE(tdc.TargetSalesAmount, 0)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_TARGETDATACHANNEL tdc
LEFT JOIN Dim_Channel  c ON tdc.ChannelName = c.ChannelName
LEFT JOIN Dim_Store    s ON tdc.TargetName  = 'Store'
LEFT JOIN Dim_Reseller r ON tdc.TargetName  = 'Reseller'
JOIN Dim_Date d
    ON  tdc.Year = d.CalendarYear
    AND d.MonthNumberOfYear = 1
    AND d.DayNumberOfMonth  = 1;

/* -----------------------------------------------------------------------------
   FACT_SALESACTUAL  — transaction-grain actual sales
   Derived measures: unit price, extended cost, and total profit are
   calculated at load time so downstream analytics stay simple.
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Fact_SalesActual (
    DimProductID        INT NOT NULL,
    DimStoreID          INT NOT NULL,
    DimResellerID       INT NOT NULL,
    DimCustomerID       INT NOT NULL,
    DimChannelID        INT NOT NULL,
    DimSaleDateID       INT NOT NULL,
    DimLocationID       INT NOT NULL,
    SalesHeaderID       INT,
    SalesDetailID       INT,
    SaleAmount          FLOAT NOT NULL,
    SaleQuantity        INT NOT NULL,
    SaleUnitPrice       FLOAT NOT NULL,
    SaleExtendedCost    FLOAT NOT NULL,
    SaleTotalProfit     FLOAT NOT NULL,
    CONSTRAINT FK_Sales_Product  FOREIGN KEY (DimProductID)  REFERENCES Dim_Product(DimProductID),
    CONSTRAINT FK_Sales_Store    FOREIGN KEY (DimStoreID)    REFERENCES Dim_Store(DimStoreID),
    CONSTRAINT FK_Sales_Reseller FOREIGN KEY (DimResellerID) REFERENCES Dim_Reseller(DimResellerID),
    CONSTRAINT FK_Sales_Customer FOREIGN KEY (DimCustomerID) REFERENCES Dim_Customer(DimCustomerID),
    CONSTRAINT FK_Sales_Channel  FOREIGN KEY (DimChannelID)  REFERENCES Dim_Channel(DimChannelID),
    CONSTRAINT FK_Sales_Date     FOREIGN KEY (DimSaleDateID) REFERENCES Dim_Date(DimDateID),
    CONSTRAINT FK_Sales_Location FOREIGN KEY (DimLocationID) REFERENCES Dim_Location(DimLocationID)
);

INSERT INTO Fact_SalesActual (
    DimProductID, DimStoreID, DimResellerID, DimCustomerID, DimChannelID,
    DimSaleDateID, DimLocationID, SalesHeaderID, SalesDetailID,
    SaleAmount, SaleQuantity, SaleUnitPrice, SaleExtendedCost, SaleTotalProfit
)
SELECT
    COALESCE(p.DimProductID, -1),
    CASE WHEN sh.StoreID    IS NOT NULL THEN COALESCE(s.DimStoreID, -1)    ELSE -1 END,
    CASE WHEN sh.ResellerID IS NOT NULL THEN COALESCE(r.DimResellerID, -1) ELSE -1 END,
    CASE WHEN sh.CustomerID IS NOT NULL THEN COALESCE(c.DimCustomerID, -1) ELSE -1 END,
    COALESCE(ch.DimChannelID, -1),
    COALESCE(d.DimDateID, -1),
    COALESCE(
        CASE
            WHEN sh.StoreID    IS NOT NULL THEN s.DimLocationID
            WHEN sh.ResellerID IS NOT NULL THEN r.DimLocationID
            WHEN sh.CustomerID IS NOT NULL THEN c.DimLocationID
            ELSE -1
        END, -1),
    sh.SalesHeaderID,
    sd.SalesDetailID,
    COALESCE(sd.SalesAmount, 0),
    COALESCE(sd.SalesQuantity, 0),
    CASE WHEN COALESCE(sd.SalesQuantity, 0) = 0 THEN 0
         ELSE COALESCE(sd.SalesAmount, 0) / COALESCE(sd.SalesQuantity, 1) END,
    COALESCE(p.Cost * sd.SalesQuantity, 0),
    COALESCE(sd.SalesAmount, 0) - COALESCE(p.Cost * sd.SalesQuantity, 0)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_SALESDETAIL sd
JOIN RETAIL_DW_STAGING.PUBLIC.STAGING_SALESHEADER sh ON sd.SalesHeaderID = sh.SalesHeaderID
LEFT JOIN Dim_Product  p  ON sd.ProductID  = p.ProductID
LEFT JOIN Dim_Store    s  ON sh.StoreID    = s.StoreID
LEFT JOIN Dim_Reseller r  ON sh.ResellerID = r.ResellerID
LEFT JOIN Dim_Customer c  ON sh.CustomerID = c.CustomerID
LEFT JOIN Dim_Channel  ch ON sh.ChannelID  = ch.ChannelID
LEFT JOIN Dim_Date     d  ON sh.Date       = d.FullDate;
