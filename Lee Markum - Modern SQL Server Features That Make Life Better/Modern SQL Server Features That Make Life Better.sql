/*
Should I kill an active query?
https://github.com/microsoft/bobsql/tree/master/sql2019book 

*/
USE WideWorldImporters
GO

-- Build a new rowmode table called OrderHistory based off of Orders
DROP TABLE IF EXISTS Sales.InvoiceLinesExtended
GO

SELECT 'Building InvoiceLinesExtended from InvoiceLines...'
GO

CREATE TABLE [Sales].[InvoiceLinesExtended](
	[InvoiceLineID] [int] IDENTITY NOT NULL,
	[InvoiceID] [int] NOT NULL,
	[StockItemID] [int] NOT NULL,
	[Description] [nvarchar](100) NOT NULL,
	[PackageTypeID] [int] NOT NULL,
	[Quantity] [int] NOT NULL,
	[UnitPrice] [decimal](18, 2) NULL,
	[TaxRate] [decimal](18, 3) NOT NULL,
	[TaxAmount] [decimal](18, 2) NOT NULL,
	[LineProfit] [decimal](18, 2) NOT NULL,
	[ExtendedPrice] [decimal](18, 2) NOT NULL,
	[LastEditedBy] [int] NOT NULL,
	[LastEditedWhen] [datetime2](7) NOT NULL,
 CONSTRAINT [PK_Sales_InvoiceLinesExtended] PRIMARY KEY CLUSTERED 
(
	[InvoiceLineID] ASC
))
GO

CREATE INDEX IX_StockItemID
ON Sales.InvoiceLinesExtended([StockItemID])
WITH(DATA_COMPRESSION=PAGE)
GO

INSERT Sales.InvoiceLinesExtended(InvoiceID, StockItemID, Description, PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, LastEditedWhen)
SELECT InvoiceID, StockItemID, Description, PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, LastEditedWhen
FROM Sales.InvoiceLines
GO

-- Table should have 228,265 rows
SELECT 'Number of rows in Sales.InvoiceLinesExtended = ', 
COUNT(*) FROM Sales.InvoiceLinesExtended
GO

SELECT 'Increasing number of rows for InvoiceLinesExtended...'
GO
-- Make the table bigger
INSERT Sales.InvoiceLinesExtended(InvoiceID, StockItemID, Description, 
PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, 
ExtendedPrice, LastEditedBy, LastEditedWhen)

SELECT InvoiceID, StockItemID, [Description], PackageTypeID, Quantity, 
UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, 
LastEditedWhen
FROM Sales.InvoiceLinesExtended
GO 4

-- Table should have 3,652,240 rows
SELECT 'Number of rows in Sales.InvoiceLinesExtended = ', COUNT(*) FROM Sales.InvoiceLinesExtended
GO

SELECT COUNT(DISTINCT(StockItemID)) FROM Sales.InvoiceLinesExtended




/***

mysmartsqlquery.sql

Should we kill this active query?
***/


USE WideWorldImporters
GO
SELECT si.CustomerID, sil.InvoiceID, sil.LineProfit
FROM Sales.Invoices si
INNER JOIN Sales.InvoiceLinesExtended sil
ON si.InvoiceID = si.InvoiceID
OPTION (MAXDOP 1)
GO


/***

Run this in another Window

Show_Active_Queries.sql

***/

/* 
Step 1: Only show requests with active queries except for this session.
New DMF in 2016 shows the active query plan with runtime stats 
while the query is running.

It's only a snapshot in time and you have to open the query plan 
and examine it each time you run the query.


*/
SELECT er.session_id, er.command, er.status, er.wait_type, er.cpu_time, er.logical_reads, eqsx.query_plan, t.text
FROM sys.dm_exec_requests er
--(New in SQL Server 2016 and returns a query plan while the query is still running)
CROSS APPLY sys.dm_exec_query_statistics_xml(er.session_id) eqsx
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) t
WHERE er.session_id <> @@SPID
GO
 
/*
Step 2: What does the plan profile look like for the active query
*/
SELECT session_id, physical_operator_name, node_id, thread_id, row_count, estimate_row_count
FROM sys.dm_exec_query_profiles
WHERE session_id <> @@SPID
ORDER BY session_id, node_id DESC
GO

/*
Demonstrating Temporal Tables
*/
USE AdventureWorks2016CTP3;
GO

/*Create backup table to experiment with. 
It has 504 rows
*/
DROP TABLE IF EXISTS Production.ProductBackup
SELECT TOP (1000) [ProductID]
      ,[Name]
      ,[ProductNumber]
      ,[MakeFlag]
      ,[FinishedGoodsFlag]
      ,[Color]
      ,[SafetyStockLevel]
      ,[ReorderPoint]
      ,[StandardCost]
      ,[ListPrice]
      ,[Size]
      ,[SizeUnitMeasureCode]
      ,[WeightUnitMeasureCode]
      ,[Weight]
      ,[DaysToManufacture]
      ,[ProductLine]
      ,[Class]
      ,[Style]
      ,[ProductSubcategoryID]
      ,[ProductModelID]
      ,[SellStartDate]
      ,[SellEndDate]
      ,[DiscontinuedDate]
      ,[rowguid]
      ,[ModifiedDate]
	  INTO Production.ProductBackup
  FROM [AdventureWorks2016CTP3].[Production].[Product]

  /*
  The temporal/"source" or original table, must have a primary key.
  */
ALTER TABLE PRODUCTION.ProductBackup ADD CONSTRAINT PK_ProductBackup PRIMARY KEY CLUSTERED (ProductId);
GO

/*

Some data that might be of interest.
We want to raise the price of all accessories by 10%.
*/
SELECT P.[Name] AS ProductName, P.ProductNumber, P.ListPrice, CAST(P.ListPrice *1.10 AS DECIMAL(9,2)) AS NewListPrice 
FROM Production.ProductBackup AS P
INNER JOIN Production.ProductSubcategory AS PSC ON P.ProductSubcategoryID = PSC.ProductSubcategoryID
INNER JOIN Production.ProductCategory AS PC ON PC.ProductCategoryID = PSC.ProductCategoryID
WHERE PC.[name] = 'Accessories';

  
/*
Enable SystemVersioning on existing table
*/

USE AdventureWorks2016CTP3;
GO
/*
Create a new schema to hold the history table
*/
CREATE SCHEMA History;

/*
Enable SystemVersioning on existing table
*/

ALTER TABLE [Production].[ProductBackup]
	ADD SysStartTime DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		     CONSTRAINT DF_SysStart DEFAULT GETUTCDATE() 
      , SysEndTime DATETIME2(7) GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
            CONSTRAINT DF_SysEnd DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
        PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime);

ALTER TABLE [Production].[ProductBackup]
SET (SYSTEM_VERSIONING = ON(HISTORY_TABLE = History.ProductBackup));

SELECT *
FROM History.ProductBackup

/*
Update some rows to populate the history table. 
We will raise the price of everything in the Accessories category by 10%.
Should be 29 rows changed.
*/

BEGIN TRAN
  UPDATE Production.ProductBackup
  SET ListPrice = CAST(ListPrice *1.10 AS DECIMAL(9,2))
  FROM Production.ProductBackup AS P
  INNER JOIN Production.ProductSubcategory AS PSC ON P.ProductSubcategoryID = PSC.ProductSubcategoryID
  INNER JOIN Production.ProductCategory AS PC ON PC.ProductCategoryID = PSC.ProductCategoryID
  WHERE PC.[name] = 'Accessories';
  
COMMIT TRAN

/*

One method to show the old data and the new data
*/
SELECT PB.[Name] AS PBName, PB.ListPrice AS CurrentListPRice, 
PBH.ListPrice AS PreviousListPrice, PBH.SysStartTime, PBH.SysendTime
FROM Production.ProductBackup  AS PB
INNER JOIN History.ProductBackup AS PBH ON PB.ProductID = PBH.ProductId --AS PB
--FOR SYSTEM_TIME ALL 
WHERE PBH.ProductID IN
(
707,708,711,842,843,844,845,846,847,848,870,
871,872,873,876,877,878,879,880,921,922,923,
928,929,930,931,932,933,934
)
ORDER BY PBH.ProductID;

/*
Second method to see the changed data
*/
SELECT ProductId,[name] AS ProductName, ListPrice, SysStartTime, SysEndTime
FROM History.ProductBackup
ORDER BY ProductId, SysStartTime ASC;

/*

This is the same as doing a UNION ALL between the temporal 
and history table.

There is also syntax for find rows that existed AS OF a 
certain System_Time value, FROM and TO certain start and end date time
values and an option for BETWEEN start and end time,
which indludes the records that were active on the end date time.
*/
SELECT *
FROM Production.ProductBackup 
FOR SYSTEM_TIME ALL ;

/*
You can change data types in the temporal table 
and the history table changes with it.
*/
ALTER TABLE [Production].[ProductBackup] 
ALTER COLUMN Name VARCHAR(100) NOT NULL

/*
You can also add columns to the temporal table
and they are added to the history table.
*/
ALTER TABLE [Production].[ProductBackup] ADD MeaningLess INT NULL


/*
Cleanup the demo
Revert the table back to a non-temporal table
*/
ALTER TABLE [Production].[ProductBackup] SET (SYSTEM_VERSIONING = OFF); 
ALTER TABLE [Production].[ProductBackup] DROP PERIOD FOR SYSTEM_TIME;

/* Drop the constraints and columns, and the history table*/
ALTER TABLE [Production].[ProductBackup] DROP CONSTRAINT DF_SysStart, DF_SysEnd;
ALTER TABLE [Production].[ProductBackup] DROP COLUMN SysStartTime, SysEndTime;
DROP TABLE History.ProductBackup

/*
Drop the History schema
*/
DROP SCHEMA History


/***Demonstrate T-SQL Enhancements***/


/*Demonstrate Drop If Exists*/

/*Execute to make the table, then execute again to 
simulate a deployment script and note the error.
*/
  USE DBAUTility;
  GO

  CREATE TABLE MyTestTable
  (
  ID INT IDENTITY (1,1),
  ProductName VARCHAR (100)
  )

/*
A previous method to test for existence then drop if it exists. 
*/
IF EXISTS (
  SELECT 1 FROM sys.objects
  WHERE object_id = object_id(N'[dbo].[MyTestTable]')
    AND type in (N'U') 
)
BEGIN
  DROP TABLE [dbo].[MyTestTable]
END;


/*Drop If Exists. */

DROP TABLE IF EXISTS MyTestTable

DROP PROCEDURE IF EXISTS dbo.GetSQLServerVersions

/****Demonstrate CREATE OR ALTER****/

USE DBAUtility;
GO
CREATE OR ALTER PROC GetSQLServerVersions 
AS 
BEGIN
	SELECT TOP 5*
	FROM dbo.SqlServerVersions
END

--Returns 5 rows just as defined above
EXEC GetSQLServerVersions

USE DBAUtility;
GO
CREATE OR ALTER PROC GetSQLServerVersions 
AS 
BEGIN
	SELECT TOP 50*
	FROM dbo.SqlServerVersions
END

--Returns 50 rows just as defined above
EXEC GetSQLServerVersions


/****Demonstrate Inline specification for Indexes****/
USE DBAUtility;
GO
DROP TABLE IF Exists t1;

--filtered index
CREATE TABLE t1
(
    c1 INT,
    index IX1 (c1) WHERE c1 > 0
);

DROP TABLE IF Exists t2;

--multi-column index
CREATE TABLE t2
(
    c1 INT,
    c2 INT,
    INDEX ix_1 NONCLUSTERED (c1,c2)
);

DROP TABLE IF Exists t3;

--multi-column unique index
CREATE TABLE t3
(
    c1 INT,
    c2 INT,
    INDEX ix_1 UNIQUE NONCLUSTERED (c1,c2)
);

DROP TABLE IF Exists t4;
-- make unique clustered index
CREATE TABLE t4
(
    c1 INT,
    c2 INT,
    INDEX ix_1 UNIQUE CLUSTERED (c1,c2)
);

/****Demo CONCAT and CONCAT_WS

https://leemarkum.com/archive/2021/09/how-to-use-the-sql-server-concat-function/

****/

USE AdventureWorks2014;
GO
--A NULL in the concatenated columns produces a NULL for MailingName
SELECT TOP 5
    Title, 
    FirstName, 
    MiddleName, 
    LastName,
    Title + ' ' + FirstName + ' ' + MiddleName + ' ' + LastName as MailingName
FROM Person.Person;

--With CONCAT(), columns with NULL values simply have those values ignored in MailingName.
SELECT TOP 5
    Title, 
    FirstName, 
    MiddleName, 
    LastName,
    CONCAT(Title,' ',FirstName,' ',MiddleName,' ', LastName) as MailingName
FROM Person.Person;

--CONCAT_WS
SELECT TOP 5 Title, FirstName, MiddleName, LastName, 
CONCAT_WS(' ',Title,FirstName,MiddleName,LastName) as MailingName 
FROM Person.Person;
