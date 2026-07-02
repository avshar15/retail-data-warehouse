/* =============================================================================
   02_DIMENSIONS.SQL
   Layer 2 of 4  |  Dimension tables (conformed, cleaned, surrogate-keyed)

   Purpose:
     Transform raw staging data into clean, analytics-ready dimension tables.
     Each dimension:
       - uses an IDENTITY surrogate key as its primary key
       - retains the natural (source-system) key for traceability
       - loads an "unknown member" (-1) row so facts never carry NULL FKs
       - applies COALESCE-based cleaning to standardize missing values

   Design note:
     Dim_Location is a shared geography dimension built by UNION-ing the
     address data from customers, stores, and resellers, tagged by source.
     This keeps location logic in one place and lets facts resolve to a
     single conformed location key.
   ============================================================================= */

USE DATABASE RETAIL_DW;
USE SCHEMA PUBLIC;

/* -----------------------------------------------------------------------------
   DIM_LOCATION  - conformed geography (customers + stores + resellers)
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Location (
    DimLocationID   INT IDENTITY(1,1) CONSTRAINT PK_DimLocationID PRIMARY KEY NOT NULL,
    Country         VARCHAR(255) NOT NULL,
    StateProvince   VARCHAR(255) NOT NULL,
    City            VARCHAR(255) NOT NULL,
    PostalCode      VARCHAR(255) NOT NULL,
    Address         VARCHAR(255),
    SourceSystem    VARCHAR(50)
);

-- Unknown member
INSERT INTO Dim_Location (DimLocationID, Country, StateProvince, City, PostalCode, Address, SourceSystem)
VALUES (-1, 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown');

-- Load distinct locations from all three source systems
INSERT INTO Dim_Location (Country, StateProvince, City, PostalCode, Address, SourceSystem)
SELECT DISTINCT
    COALESCE(c.Country, 'Unknown'),
    COALESCE(c.StateProvince, 'Unknown'),
    COALESCE(c.City, 'Unknown'),
    COALESCE(c.PostalCode, 'Unknown'),
    COALESCE(c.Address, 'Unknown'),
    'Customer'
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_CUSTOMER c
UNION
SELECT DISTINCT
    COALESCE(s.Country, 'Unknown'),
    COALESCE(s.StateProvince, 'Unknown'),
    COALESCE(s.City, 'Unknown'),
    COALESCE(s.PostalCode, 'Unknown'),
    COALESCE(s.Address, 'Unknown'),
    'Store'
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_STORE s
UNION
SELECT DISTINCT
    COALESCE(r.Country, 'Unknown'),
    COALESCE(r.StateProvince, 'Unknown'),
    COALESCE(r.City, 'Unknown'),
    COALESCE(r.PostalCode, 'Unknown'),
    COALESCE(r.Address, 'Unknown'),
    'Reseller'
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_RESELLER r;

/* -----------------------------------------------------------------------------
   DIM_PRODUCT  - snowflaked from product -> type -> category
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Product (
    DimProductID        INT IDENTITY(1,1) CONSTRAINT PK_DimProductID PRIMARY KEY NOT NULL,
    ProductID           INTEGER NOT NULL,
    ProductName         VARCHAR(255) NOT NULL,
    ProductTypeID       INTEGER NOT NULL,
    ProductType         VARCHAR(255) NOT NULL,
    ProductCategoryID   INTEGER NOT NULL,
    ProductCategory     VARCHAR(255) NOT NULL,
    Color               VARCHAR(255) NOT NULL,
    Style               VARCHAR(255) NOT NULL,
    UnitOfMeasureID     INTEGER,
    Weight              FLOAT,
    Price               FLOAT NOT NULL,
    Cost                FLOAT NOT NULL,
    WholesalePrice      FLOAT
);

INSERT INTO Dim_Product (
    DimProductID, ProductID, ProductName, ProductTypeID, ProductType,
    ProductCategoryID, ProductCategory, Color, Style, UnitOfMeasureID,
    Weight, Price, Cost, WholesalePrice
)
VALUES (-1, -1, 'Unknown', -1, 'Unknown', -1, 'Unknown', 'Unknown', 'Unknown', -1, -1, -1, -1, -1);

INSERT INTO Dim_Product (
    ProductID, ProductName, ProductTypeID, ProductType, ProductCategoryID,
    ProductCategory, Color, Style, UnitOfMeasureID, Weight, Price, Cost, WholesalePrice
)
SELECT
    sp.ProductID,
    COALESCE(sp.Product, 'Unknown'),
    COALESCE(sp.ProductTypeID, -1),
    COALESCE(pt.ProductType, 'Unknown'),
    COALESCE(pt.ProductCategoryID, -1),
    COALESCE(pc.ProductCategory, 'Unknown'),
    COALESCE(sp.Color, 'Unknown'),
    COALESCE(sp.Style, 'Unknown'),
    COALESCE(sp.UnitOfMeasureID, -1),
    COALESCE(sp.Weight, -1),
    COALESCE(sp.Price, -1),
    COALESCE(sp.Cost, -1),
    COALESCE(sp.WholesalePrice, -1)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_PRODUCT sp
LEFT JOIN RETAIL_DW_STAGING.PUBLIC.STAGING_PRODUCTTYPE pt
    ON sp.ProductTypeID = pt.ProductTypeID
LEFT JOIN RETAIL_DW_STAGING.PUBLIC.STAGING_PRODUCTCATEGORY pc
    ON pt.ProductCategoryID = pc.ProductCategoryID;

/* -----------------------------------------------------------------------------
   DIM_CUSTOMER  - resolves to conformed location key
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Customer (
    DimCustomerID   INT IDENTITY(1,1) CONSTRAINT PK_DimCustomerID PRIMARY KEY NOT NULL,
    CustomerID      VARCHAR(255) NOT NULL,
    FirstName       VARCHAR(255) NOT NULL,
    LastName        VARCHAR(255) NOT NULL,
    FullName        VARCHAR(511) NOT NULL,
    Gender          VARCHAR(255) NOT NULL,
    EmailAddress    VARCHAR(255) NOT NULL,
    DimLocationID   INTEGER NOT NULL
);

INSERT INTO Dim_Customer (DimCustomerID, CustomerID, FirstName, LastName, FullName, Gender, EmailAddress, DimLocationID)
VALUES (-1, 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', -1);

INSERT INTO Dim_Customer (CustomerID, FirstName, LastName, FullName, Gender, EmailAddress, DimLocationID)
SELECT
    cust.CustomerID,
    COALESCE(cust.FirstName, 'Unknown'),
    COALESCE(cust.LastName, 'Unknown'),
    COALESCE(cust.FirstName, 'Unknown') || ' ' || COALESCE(cust.LastName, 'Unknown'),
    COALESCE(cust.Gender, 'Unknown'),
    COALESCE(cust.EmailAddress, 'Unknown'),
    COALESCE(loc.DimLocationID, -1)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_CUSTOMER cust
LEFT JOIN Dim_Location loc
    ON  loc.Country       = COALESCE(cust.Country, 'Unknown')
    AND loc.StateProvince = COALESCE(cust.StateProvince, 'Unknown')
    AND loc.City          = COALESCE(cust.City, 'Unknown')
    AND loc.PostalCode    = COALESCE(cust.PostalCode, 'Unknown')
    AND loc.SourceSystem  = 'Customer';

/* -----------------------------------------------------------------------------
   DIM_RESELLER
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Reseller (
    DimResellerID   INT IDENTITY(1,1) CONSTRAINT PK_DimResellerID PRIMARY KEY NOT NULL,
    ResellerID      VARCHAR(255) NOT NULL,
    ResellerName    VARCHAR(255) NOT NULL,
    Contact         VARCHAR(255) NOT NULL,
    EmailAddress    VARCHAR(255) NOT NULL,
    DimLocationID   INTEGER NOT NULL
);

INSERT INTO Dim_Reseller (DimResellerID, ResellerID, ResellerName, Contact, EmailAddress, DimLocationID)
VALUES (-1, 'Unknown', 'Unknown', 'Unknown', 'Unknown', -1);

INSERT INTO Dim_Reseller (ResellerID, ResellerName, Contact, EmailAddress, DimLocationID)
SELECT
    rs.ResellerID,
    COALESCE(rs.ResellerName, 'Unknown'),
    COALESCE(rs.Contact, 'Unknown'),
    COALESCE(rs.EmailAddress, 'Unknown'),
    COALESCE(loc.DimLocationID, -1)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_RESELLER rs
LEFT JOIN Dim_Location loc
    ON  loc.Country       = COALESCE(rs.Country, 'Unknown')
    AND loc.StateProvince = COALESCE(rs.StateProvince, 'Unknown')
    AND loc.City          = COALESCE(rs.City, 'Unknown')
    AND loc.PostalCode    = COALESCE(rs.PostalCode, 'Unknown')
    AND loc.SourceSystem  = 'Reseller';

/* -----------------------------------------------------------------------------
   DIM_STORE
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Store (
    DimStoreID      INT IDENTITY(1,1) CONSTRAINT PK_DimStoreID PRIMARY KEY NOT NULL,
    StoreID         INTEGER NOT NULL,
    StoreNumber     INTEGER NOT NULL,
    StoreManager    VARCHAR(255) NOT NULL,
    DimLocationID   INTEGER NOT NULL
);

INSERT INTO Dim_Store (DimStoreID, StoreID, StoreNumber, StoreManager, DimLocationID)
VALUES (-1, -1, -1, 'Unknown', -1);

INSERT INTO Dim_Store (StoreID, StoreNumber, StoreManager, DimLocationID)
SELECT
    st.StoreID,
    COALESCE(st.StoreNumber, -1),
    COALESCE(st.StoreManager, 'Unknown'),
    COALESCE(loc.DimLocationID, -1)
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_STORE st
LEFT JOIN Dim_Location loc
    ON  loc.Country       = COALESCE(st.Country, 'Unknown')
    AND loc.StateProvince = COALESCE(st.StateProvince, 'Unknown')
    AND loc.City          = COALESCE(st.City, 'Unknown')
    AND loc.PostalCode    = COALESCE(st.PostalCode, 'Unknown')
    AND loc.SourceSystem  = 'Store';

/* -----------------------------------------------------------------------------
   DIM_CHANNEL  - snowflaked into channel category
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Channel (
    DimChannelID        INT IDENTITY(1,1) CONSTRAINT PK_DimChannelID PRIMARY KEY NOT NULL,
    ChannelID           INTEGER NOT NULL,
    ChannelName         VARCHAR(255) NOT NULL,
    ChannelCategoryID   INTEGER NOT NULL,
    ChannelCategory     VARCHAR(255) NOT NULL
);

INSERT INTO Dim_Channel (DimChannelID, ChannelID, ChannelName, ChannelCategoryID, ChannelCategory)
VALUES (-1, -1, 'Unknown', -1, 'Unknown');

INSERT INTO Dim_Channel (ChannelID, ChannelName, ChannelCategoryID, ChannelCategory)
SELECT
    ch.ChannelID,
    COALESCE(ch.Channel, 'Unknown'),
    COALESCE(ch.ChannelCategoryID, -1),
    COALESCE(cc.ChannelCategory, 'Unknown')
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_CHANNEL ch
LEFT JOIN RETAIL_DW_STAGING.PUBLIC.STAGING_CHANNELCATEGORY cc
    ON ch.ChannelCategoryID = cc.ChannelCategoryID;

/* -----------------------------------------------------------------------------
   DIM_DATE  - derived from sales header dates
   -------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE Dim_Date (
    DimDateID           INT AUTOINCREMENT PRIMARY KEY,
    FullDate            DATE,
    DayNameOfWeek       VARCHAR(50),
    DayNumberOfMonth    INT,
    MonthName           VARCHAR(50),
    MonthNumberOfYear   INT,
    CalendarYear        INT
);

INSERT INTO Dim_Date (FullDate, DayNameOfWeek, DayNumberOfMonth, MonthName, MonthNumberOfYear, CalendarYear)
SELECT DISTINCT
    "DATE"                              AS FullDate,
    TO_VARCHAR("DATE", 'Day')           AS DayNameOfWeek,
    TO_NUMBER(TO_CHAR("DATE", 'DD'))    AS DayNumberOfMonth,
    TO_VARCHAR("DATE", 'Month')         AS MonthName,
    TO_NUMBER(TO_CHAR("DATE", 'MM'))    AS MonthNumberOfYear,
    TO_NUMBER(TO_CHAR("DATE", 'YYYY'))  AS CalendarYear
FROM RETAIL_DW_STAGING.PUBLIC.STAGING_SALESHEADER
WHERE "DATE" IS NOT NULL;
