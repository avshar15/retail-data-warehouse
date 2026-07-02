/* =============================================================================
   01_STAGING.SQL
   Layer 1 of 4  |  Raw ingestion into Snowflake

   Purpose:
     Land raw source CSVs (product, sales, channel, store, reseller, targets,
     etc.) into a dedicated STAGING database with no transformation applied.
     This is the "load" in ELT - data is moved as-is, and all cleaning /
     conforming happens downstream in SQL (see 02_dimensions.sql).

   Source:
     CSV extracts of an operational retail system, staged in Azure Blob
     Storage, then loaded into Snowflake staging tables.

   Note on loading:
     Files were loaded from an Azure Blob Storage container into these staging
     tables via the Snowflake UI / COPY INTO. A representative COPY INTO block
     is included below for STAGING_CHANNEL to document the mechanism; the same
     pattern applies to every staging table. Blob credentials were environment-
     provided and are intentionally omitted.
   ============================================================================= */

CREATE DATABASE IF NOT EXISTS RETAIL_DW_STAGING;
USE DATABASE RETAIL_DW_STAGING;
USE SCHEMA PUBLIC;

/* -----------------------------------------------------------------------------
   STAGING TABLE DDL
   Column structures mirror the source CSVs exactly (raw, untyped-friendly).
   -------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE STAGING_CHANNEL (
    ChannelID           INTEGER,
    ChannelCategoryID   INTEGER,
    Channel             VARCHAR(255),
    CreatedDate         VARCHAR(255),
    CreatedBy           VARCHAR(255),
    ModifiedDate        VARCHAR(255),
    ModifiedBy          VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_CHANNELCATEGORY (
    ChannelCategoryID   INTEGER,
    ChannelCategory     VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_PRODUCT (
    ProductID           INTEGER,
    Product             VARCHAR(255),
    ProductTypeID       INTEGER,
    Color               VARCHAR(255),
    Style               VARCHAR(255),
    UnitOfMeasureID     INTEGER,
    Weight              FLOAT,
    Price               FLOAT,
    Cost                FLOAT,
    WholesalePrice      FLOAT
);

CREATE OR REPLACE TABLE STAGING_PRODUCTTYPE (
    ProductTypeID       INTEGER,
    ProductCategoryID   INTEGER,
    ProductType         VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_PRODUCTCATEGORY (
    ProductCategoryID   INTEGER,
    ProductCategory     VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_CUSTOMER (
    CustomerID          VARCHAR(255),
    FirstName           VARCHAR(255),
    LastName            VARCHAR(255),
    Gender              VARCHAR(255),
    EmailAddress        VARCHAR(255),
    Address             VARCHAR(255),
    City                VARCHAR(255),
    StateProvince       VARCHAR(255),
    Country             VARCHAR(255),
    PostalCode          VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_RESELLER (
    ResellerID          VARCHAR(255),
    ResellerName        VARCHAR(255),
    Contact             VARCHAR(255),
    EmailAddress        VARCHAR(255),
    Address             VARCHAR(255),
    City                VARCHAR(255),
    StateProvince       VARCHAR(255),
    Country             VARCHAR(255),
    PostalCode          VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_STORE (
    StoreID             INTEGER,
    StoreNumber         INTEGER,
    StoreManager        VARCHAR(255),
    Address             VARCHAR(255),
    City                VARCHAR(255),
    StateProvince       VARCHAR(255),
    Country             VARCHAR(255),
    PostalCode          VARCHAR(255),
    PhoneNumber         VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_SALESHEADER (
    SalesHeaderID       INTEGER,
    "DATE"              DATE,
    ChannelID           INTEGER,
    StoreID             INTEGER,
    CustomerID          VARCHAR(255),
    ResellerID          VARCHAR(255)
);

CREATE OR REPLACE TABLE STAGING_SALESDETAIL (
    SalesDetailID       INTEGER,
    SalesHeaderID       INTEGER,
    ProductID           INTEGER,
    SalesQuantity       INTEGER,
    SalesAmount         FLOAT
);

CREATE OR REPLACE TABLE STAGING_TARGETDATAPRODUCT (
    ProductID           INTEGER,
    Product             VARCHAR(255),
    Year                INTEGER,
    SalesQuantityTarget INTEGER
);

CREATE OR REPLACE TABLE STAGING_TARGETDATACHANNEL (
    Year                INTEGER,
    ChannelName         VARCHAR(255),
    TargetName          VARCHAR(255),
    TargetSalesAmount   FLOAT
);

/* -----------------------------------------------------------------------------
   LOADING FROM AZURE BLOB STORAGE  (representative example)

   Each staging table was populated from its corresponding CSV in an Azure
   Blob Storage container. The pattern below documents the mechanism for one
   table; the same COPY INTO approach applies to all staging tables.
   -------------------------------------------------------------------------- */

-- Example external stage pointing at the Azure Blob container:
-- CREATE OR REPLACE STAGE azure_retail_stage
--   URL = 'azure://<account>.blob.core.windows.net/<container>'
--   CREDENTIALS = ( AZURE_SAS_TOKEN = '<provided-token>' )
--   FILE_FORMAT = ( TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1 );

-- Example load into one staging table:
-- COPY INTO STAGING_CHANNEL
--   FROM @azure_retail_stage/channel.csv
--   FILE_FORMAT = ( TYPE = CSV SKIP_HEADER = 1 );

/* Verification (run after each load) */
-- SELECT * FROM STAGING_CHANNEL;
-- SELECT * FROM STAGING_STORE;
-- SELECT * FROM STAGING_TARGETDATACHANNEL;
