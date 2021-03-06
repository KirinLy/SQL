---------------------------------------------------------------------
-- T-SQL Querying (Microsoft Press, 2015)
-- Chapter 04 - Grouping, Pivoting and Windowing
-- © Itzik Ben-Gan
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Window Functions
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Aggregate Window Functions
---------------------------------------------------------------------

-- Sample data
SET NOCOUNT ON;
USE tempdb;

-- OrderValues table
IF OBJECT_ID(N'dbo.OrderValues', N'U') IS NOT NULL DROP TABLE dbo.OrderValues;

SELECT * INTO dbo.OrderValues FROM TSQLV3.Sales.OrderValues;

ALTER TABLE dbo.OrderValues ADD CONSTRAINT PK_OrderValues PRIMARY KEY(orderid);
GO

-- EmpOrders table
IF OBJECT_ID(N'dbo.EmpOrders', N'U') IS NOT NULL DROP TABLE dbo.EmpOrders;

SELECT empid, ISNULL(ordermonth, CAST('19000101' AS DATE)) AS ordermonth, qty, val, numorders 
INTO dbo.EmpOrders
FROM TSQLV3.Sales.EmpOrders;

ALTER TABLE dbo.EmpOrders ADD CONSTRAINT PK_EmpOrders PRIMARY KEY(empid, ordermonth);
GO

-- Transactions table
IF OBJECT_ID('dbo.Transactions', 'U') IS NOT NULL DROP TABLE dbo.Transactions;
IF OBJECT_ID('dbo.Accounts', 'U') IS NOT NULL DROP TABLE dbo.Accounts;

CREATE TABLE dbo.Accounts
(
  actid INT NOT NULL CONSTRAINT PK_Accounts PRIMARY KEY
);

CREATE TABLE dbo.Transactions
(
  actid  INT   NOT NULL,
  tranid INT   NOT NULL,
  val    MONEY NOT NULL,
  CONSTRAINT PK_Transactions PRIMARY KEY(actid, tranid)
);

DECLARE
  @num_partitions     AS INT = 100,
  @rows_per_partition AS INT = 20000;

INSERT INTO dbo.Accounts WITH (TABLOCK) (actid)
  SELECT NP.n
  FROM TSQLV3.dbo.GetNums(1, @num_partitions) AS NP;

INSERT INTO dbo.Transactions WITH (TABLOCK) (actid, tranid, val)
  SELECT NP.n, RPP.n,
    (ABS(CHECKSUM(NEWID())%2)*2-1) * (1 + ABS(CHECKSUM(NEWID())%5))
  FROM TSQLV3.dbo.GetNums(1, @num_partitions) AS NP
    CROSS JOIN TSQLV3.dbo.GetNums(1, @rows_per_partition) AS RPP;
GO

---------------------------------------------------------------------
-- Limitations of data analysis calculations without window functions
---------------------------------------------------------------------

-- Grouped query
SELECT custid, SUM(val) AS custtotal
FROM dbo.OrderValues
GROUP BY custid;
GO

-- Following fails
SELECT custid, val, SUM(val) AS custtotal
FROM dbo.OrderValues
GROUP BY custid;
GO

-- Subqueries
SELECT orderid, custid, val,
  val / (SELECT SUM(val) FROM dbo.OrderValues) AS pctall,
  val / (SELECT SUM(val) FROM dbo.OrderValues AS O2
         WHERE O2.custid = O1.custid) AS pctcust
FROM dbo.OrderValues AS O1;

-- Formatted
SELECT orderid, custid, val,
  CAST(100. *
    val / (SELECT SUM(val) FROM dbo.OrderValues)
             AS NUMERIC(5, 2)) AS pctall,
  CAST(100. *
    val /  (SELECT SUM(val) FROM dbo.OrderValues AS O2
            WHERE O2.custid = O1.custid)
             AS NUMERIC(5, 2)) AS pctcust
FROM dbo.OrderValues AS O1
ORDER BY custid;

-- Add elements to underlying query, e.g., a filter
-- Following query has a bug
SELECT orderid, custid, val,
  CAST(100. *
    val / (SELECT SUM(val) FROM dbo.OrderValues)
             AS NUMERIC(5, 2)) AS pctall,
  CAST(100. *
    val /  (SELECT SUM(val) FROM dbo.OrderValues AS O2
            WHERE O2.custid = O1.custid)
             AS NUMERIC(5, 2)) AS pctcust
FROM dbo.OrderValues AS O1
WHERE orderdate >= '20150101'
ORDER BY custid;

-- With window functions
SELECT orderid, custid, val,
  val / SUM(val) OVER() AS pctall,
  val / SUM(val) OVER(PARTITION BY custid) AS pctcust
FROM dbo.OrderValues;

-- Formatted
SELECT orderid, custid, val,
  CAST(100. * val / SUM(val) OVER()                    AS NUMERIC(5, 2)) AS pctall,
  CAST(100. * val / SUM(val) OVER(PARTITION BY custid) AS NUMERIC(5, 2)) AS pctcust
FROM dbo.OrderValues
ORDER BY custid;

-- With a filter
SELECT orderid, custid, val,
  CAST(100. * val / SUM(val) OVER()                    AS NUMERIC(5, 2)) AS pctall,
  CAST(100. * val / SUM(val) OVER(PARTITION BY custid) AS NUMERIC(5, 2)) AS pctcust
FROM dbo.OrderValues
WHERE orderdate >= '20150101'
ORDER BY custid;

---------------------------------------------------------------------
-- Window Elements
---------------------------------------------------------------------

SELECT empid, ordermonth, qty,
  SUM(qty) OVER(PARTITION BY empid
                ORDER BY ordermonth
                ROWS BETWEEN UNBOUNDED PRECEDING
                         AND CURRENT ROW) AS runqty
FROM dbo.EmpOrders;

---------------------------------------------------------------------
-- Window Partition Clause
---------------------------------------------------------------------

SELECT orderid, custid, val,
  CAST(100. * val / SUM(val) OVER()                    AS NUMERIC(5, 2)) AS pctall,
  CAST(100. * val / SUM(val) OVER(PARTITION BY custid) AS NUMERIC(5, 2)) AS pctcust
FROM dbo.OrderValues
ORDER BY custid;

-- Optimization

SELECT actid, tranid, val,
  val / SUM(val) OVER() AS pctall,
  val / SUM(val) OVER(PARTITION BY actid) AS pctact
FROM dbo.Transactions;

-- With grouped queries and joins
WITH GrandAgg AS
(
  SELECT SUM(val) AS sumall FROM dbo.Transactions
),
ActAgg AS
(
  SELECT actid, SUM(val) AS sumact
  FROM dbo.Transactions
  GROUP BY actid
)
SELECT T.actid, T.tranid, T.val,
  T.val / GA.sumall AS pctall,
  T.val / AA.sumact AS pctact
FROM dbo.Transactions AS T
  CROSS JOIN GrandAgg AS GA
  INNER JOIN ActAgg AS AA
    ON AA.actid = T.actid;

-- Grouping and windowing

-- Grouped query
SELECT custid, SUM(val) AS custtotal
FROM dbo.OrderValues
GROUP BY custid;
GO

-- Attempt to get percent of grand total
SELECT custid, SUM(val) AS custtotal,
  SUM(val) / SUM(val) OVER() AS pct
FROM dbo.OrderValues
GROUP BY custid;
GO

-- Need to apply windowed SUM to grouped SUM
SELECT custid, SUM(val) AS custtotal,
  SUM(val) / SUM(SUM(val)) OVER() AS pct
FROM dbo.OrderValues
GROUP BY custid;

---------------------------------------------------------------------
-- Window Frame 
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Window Frame Unit: ROWS
---------------------------------------------------------------------

-- ROWS UNBOUNDED PRECEDING

-- Running totals
SELECT empid, ordermonth, qty,
  SUM(qty) OVER(PARTITION BY empid
                ORDER BY ordermonth
                ROWS BETWEEN UNBOUNDED PRECEDING
                         AND CURRENT ROW) AS runqty
FROM dbo.EmpOrders;

-- Shorter form of frame
SELECT empid, ordermonth, qty,
  SUM(qty) OVER(PARTITION BY empid
                ORDER BY ordermonth
                ROWS UNBOUNDED PRECEDING) AS runqty
FROM dbo.EmpOrders;

-- Alternative without window function
SELECT O1.empid, O1.ordermonth, O1.qty,
  SUM(O2.qty) AS runqty
FROM dbo.EmpOrders AS O1
  INNER JOIN dbo.EmpOrders AS O2
    ON O2.empid = O1.empid
       AND O2.ordermonth <= O1.ordermonth
GROUP BY O1.empid, O1.ordermonth, O1.qty;

-- Optimization

-- Window function (fast track)
SELECT actid, tranid, val,
  SUM(val) OVER(PARTITION BY actid
                ORDER BY tranid
                ROWS UNBOUNDED PRECEDING) AS balance
FROM dbo.Transactions;

-- Without window function
SELECT T1.actid, T1.tranid, T1.val, SUM(T2.val) AS balance
FROM dbo.Transactions AS T1
  INNER JOIN dbo.Transactions AS T2
    ON T2.actid = T1.actid
       AND T2.tranid <= T1.tranid
GROUP BY T1.actid, T1.tranid, T1.val;

-- Row offset

-- Moving average of last three recorded periods
SELECT empid, ordermonth, 
  AVG(qty) OVER(PARTITION BY empid
                ORDER BY ordermonth
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avgqty
FROM dbo.EmpOrders;

-- Moving average of last 100 transactions
-- Cumulative aggregates optimization
SELECT actid, tranid, val,
  AVG(val) OVER(PARTITION BY actid
                ORDER BY tranid
                ROWS BETWEEN 99 PRECEDING AND CURRENT ROW) AS avg100
FROM dbo.Transactions;

-- Moving maximum of last 100 transactions
-- No special optimization
SELECT actid, tranid, val,
  MAX(val) OVER(PARTITION BY actid
                ORDER BY tranid
                ROWS BETWEEN 99 PRECEDING AND CURRENT ROW) AS max100
FROM dbo.Transactions;

-- Improved parallelism with APPLY

-- Optimized query
SELECT A.actid, D.tranid, D.val, D.max100
FROM dbo.Accounts AS A
  CROSS APPLY (SELECT tranid, val,
                 MAX(val) OVER(ORDER BY tranid
                               ROWS BETWEEN 99 PRECEDING AND CURRENT ROW) AS max100
               FROM dbo.Transactions AS T
               WHERE T.actid = A.actid) AS D;

---------------------------------------------------------------------
-- Window Frame Unit: RANGE
---------------------------------------------------------------------

-- Standard query (not support in SQL Server)
SELECT empid, ordermonth, qty,
  SUM(qty) OVER(PARTITION BY empid
                ORDER BY ordermonth
                RANGE BETWEEN INTERVAL '2' MONTH PRECEDING
                          AND CURRENT ROW) AS sum3month
FROM dbo.EmpOrders;
GO

-- Alternatives in SQL Server

-- Pad data with missing entries and use ROWS option
DECLARE
  @frommonth AS DATE = '20130701',
  @tomonth   AS DATE = '20150501';

WITH M AS
(
  SELECT DATEADD(month, N.n, @frommonth) AS ordermonth
  FROM TSQLV3.dbo.GetNums(0, DATEDIFF(month, @frommonth, @tomonth)) AS N
),
R AS
(
  SELECT E.empid, M.ordermonth, EO.qty,
    SUM(EO.qty) OVER(PARTITION BY E.empid
                  ORDER BY M.ordermonth
                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS sum3month
  FROM TSQLV3.HR.Employees AS E CROSS JOIN M
    LEFT OUTER JOIN dbo.EmpOrders AS EO
      ON E.empid = EO.empid
         AND M.ordermonth = EO.ordermonth
)
SELECT empid, ordermonth, qty, sum3month
FROM R
WHERE qty IS NOT NULL;

-- Join and group
SELECT O1.empid, O1.ordermonth, O1.qty,
  SUM(O2.qty) AS sum3month
FROM dbo.EmpOrders AS O1
  INNER JOIN dbo.EmpOrders AS O2
    ON O2.empid = O1.empid
    AND O2.ordermonth
      BETWEEN DATEADD(month, -2, O1.ordermonth)
          AND O1.ordermonth
GROUP BY O1.empid, O1.ordermonth, O1.qty
ORDER BY O1.empid, O1.ordermonth;

-- With UNBOUNDED and CURRENT ROW as delimiters
SELECT orderid, orderdate, val,
  SUM(val) OVER(ORDER BY orderdate ROWS UNBOUNDED PRECEDING) AS sumrows,
  SUM(val) OVER(ORDER BY orderdate RANGE UNBOUNDED PRECEDING) AS sumrange
FROM dbo.OrderValues;

-- Optimization

-- ROWS, in-memory spool
SELECT actid, tranid, val,
  SUM(val) OVER(PARTITION BY actid
                ORDER BY tranid
                ROWS UNBOUNDED PRECEDING) AS balance
FROM dbo.Transactions;

-- RANGE, on-disk spool
SELECT actid, tranid, val,
  SUM(val) OVER(PARTITION BY actid
                ORDER BY tranid
                RANGE UNBOUNDED PRECEDING) AS balance
FROM dbo.Transactions;

-- YTD
SELECT custid, orderid, orderdate, val,
  SUM(val) OVER(PARTITION BY custid, YEAR(orderdate)
                ORDER BY orderdate
                RANGE UNBOUNDED PRECEDING) AS YTD_val
FROM dbo.OrderValues;

-- With grouped data
SELECT custid, orderdate,
  SUM(SUM(val)) OVER(PARTITION BY custid, YEAR(orderdate)
                     ORDER BY orderdate
                     ROWS UNBOUNDED PRECEDING) AS YTD_val
FROM dbo.OrderValues
GROUP BY custid, orderdate;

---------------------------------------------------------------------
-- Ranking Window Functions
---------------------------------------------------------------------

-- Creating and populating the Orders table
SET NOCOUNT ON;
USE tempdb;

IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;

CREATE TABLE dbo.Orders
(
  orderid   INT        NOT NULL,
  orderdate DATE       NOT NULL,
  empid     INT        NOT NULL,
  custid    VARCHAR(5) NOT NULL,
  qty       INT        NOT NULL,
  CONSTRAINT PK_Orders PRIMARY KEY (orderid)
);
GO

INSERT INTO dbo.Orders(orderid, orderdate, empid, custid, qty)
  VALUES(30001, '20130802', 3, 'B', 10),
        (10001, '20131224', 1, 'C', 10),
        (10005, '20131224', 1, 'A', 30),
        (40001, '20140109', 4, 'A', 40),
        (10006, '20140118', 1, 'C', 10),
        (20001, '20140212', 2, 'B', 20),
        (40005, '20140212', 4, 'A', 10),
        (20002, '20140216', 2, 'C', 20),
        (30003, '20140418', 3, 'B', 15),
        (30004, '20140418', 3, 'B', 20),
        (30007, '20140907', 3, 'C', 30);
GO

-- Ranking
SELECT orderid, qty,
  ROW_NUMBER() OVER(ORDER BY qty) AS rownum,
  RANK()       OVER(ORDER BY qty) AS rnk,
  DENSE_RANK() OVER(ORDER BY qty) AS densernk,
  NTILE(4)     OVER(ORDER BY qty) AS ntile4
FROM dbo.Orders;

-- Example with partitioning
SELECT custid, orderid, qty,
  ROW_NUMBER() OVER(PARTITION BY custid ORDER BY orderid) AS rownum
FROM dbo.Orders
ORDER BY custid, orderid;

-- Optimization (run above query with and without POC index)
CREATE UNIQUE INDEX idx_cid_oid_i_qty ON dbo.Orders(custid, orderid) INCLUDE(qty);

-- Don't care about order 
SELECT orderid, orderdate, custid, empid, qty,
  ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS rownum
FROM dbo.Orders;

---------------------------------------------------------------------
-- Offset Window Functions
---------------------------------------------------------------------

-- FIRST_VALUE and LAST_VALUE
SELECT custid, orderid, orderdate, qty,
  FIRST_VALUE(qty) OVER(PARTITION BY custid
                        ORDER BY orderdate, orderid
                        ROWS BETWEEN UNBOUNDED PRECEDING
                                 AND CURRENT ROW) AS firstqty,
  LAST_VALUE(qty)  OVER(PARTITION BY custid
                        ORDER BY orderdate, orderid
                        ROWS BETWEEN CURRENT ROW
                                 AND UNBOUNDED FOLLOWING) AS lastqty
FROM dbo.Orders
ORDER BY custid, orderdate, orderid;

-- LAG and LEAD
SELECT custid, orderid, orderdate, qty,
  LAG(qty)  OVER(PARTITION BY custid
                 ORDER BY orderdate, orderid) AS prevqty,
  LEAD(qty) OVER(PARTITION BY custid
                 ORDER BY orderdate, orderid) AS nextqty
FROM dbo.Orders
ORDER BY custid, orderdate, orderid;

---------------------------------------------------------------------
-- Statistical Window Functions
---------------------------------------------------------------------

-- Percentile rank and cumulative distribution
USE TSQLV3;

SELECT testid, studentid, score,
  CAST( 100.00 *
    PERCENT_RANK() OVER(PARTITION BY testid ORDER BY score)
      AS NUMERIC(5, 2) ) AS percentrank,
  CAST( 100.00 *
    CUME_DIST() OVER(PARTITION BY testid ORDER BY score)
      AS NUMERIC(5, 2) ) AS cumedist
FROM Stats.Scores;

-- Percentiles
SELECT testid, studentid, score,
  PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY score)
    OVER(PARTITION BY testid) AS mediandisc,
  PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY score)
    OVER(PARTITION BY testid) AS mediancont
FROM Stats.Scores;
GO

-- As ordered set functions (not supported in SQL Server)
SELECT testid,
  PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY score) AS mediandisc,
  PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY score) AS mediancont
FROM Stats.Scores
GROUP BY testid;
GO

-- SQL Server altrnative
SELECT DISTINCT testid,
  PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY score)
    OVER(PARTITION BY testid) AS mediandisc,
  PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY score)
    OVER(PARTITION BY testid) AS mediancont
FROM Stats.Scores;

---------------------------------------------------------------------
-- Gaps and Islands
---------------------------------------------------------------------

-- Sample data
SET NOCOUNT ON;
USE tempdb;
IF OBJECT_ID('dbo.T1', 'U') IS NOT NULL DROP TABLE dbo.T1;

CREATE TABLE dbo.T1(col1 INT NOT NULL CONSTRAINT PK_T1 PRIMARY KEY);
GO

INSERT INTO dbo.T1(col1) VALUES(1),(2),(3),(7),(8),(9),(11),(15),(16),(17),(28);

-- Gaps

-- Cur - Next pairs
SELECT col1 AS cur, LEAD(col1) OVER(ORDER BY col1) AS nxt
FROM dbo.T1;

-- Solution query
WITH C AS
(
  SELECT col1 AS cur, LEAD(col1) OVER(ORDER BY col1) AS nxt
  FROM dbo.T1
)
SELECT cur + 1 AS range_from, nxt - 1 AS range_to
FROM C
WHERE nxt - cur > 1;

-- Islands

-- Identifying the pattern
SELECT col1, ROW_NUMBER() OVER(ORDER BY col1) AS rownum
FROM dbo.T1;

-- Group identifier
SELECT col1, col1 - ROW_NUMBER() OVER(ORDER BY col1) AS grp
FROM dbo.T1;

-- Solution query
WITH C AS
(
  SELECT col1, col1 - ROW_NUMBER() OVER(ORDER BY col1) AS grp
  FROM dbo.T1
)
SELECT MIN(col1) AS range_from, MAX(col1) AS range_to
FROM C
GROUP BY grp;

-- When duplicates are possible
WITH C AS
(
  SELECT col1, col1 - DENSE_RANK() OVER(ORDER BY col1) AS grp
  FROM dbo.T1
)
SELECT MIN(col1) AS range_from, MAX(col1) AS range_to
FROM C
GROUP BY grp;

-- Islands with date and time data

USE TSQLV3;

CREATE UNIQUE INDEX idx_sid_sd_oid
  ON Sales.Orders(shipperid, shippeddate, orderid)
WHERE shippeddate IS NOT NULL;

-- Islands of ship dates per shipper
WITH C AS
(
  SELECT shipperid, shippeddate,
    DATEADD(
      day,
      -1 * DENSE_RANK() OVER(PARTITION BY shipperid ORDER BY shippeddate),
      shippeddate) AS grp
  FROM Sales.Orders
  WHERE shippeddate IS NOT NULL
)
SELECT shipperid,
  MIN(shippeddate) AS fromdate,
  MAX(shippeddate) AS todate,
  COUNT(*) as numorders
FROM C
GROUP BY shipperid, grp;

-- Ignore gaps of up to 7 days

-- Start flag
SELECT shipperid, shippeddate, orderid,
  CASE WHEN DATEDIFF(day, 
    LAG(shippeddate) OVER(PARTITION BY shipperid ORDER BY shippeddate, orderid),
    shippeddate) <= 7 THEN 0 ELSE 1 END AS startflag
FROM Sales.Orders
WHERE shippeddate IS NOT NULL;

-- Group identifier
WITH C1 AS
(
  SELECT shipperid, shippeddate, orderid,
    CASE WHEN DATEDIFF(day,
      LAG(shippeddate) OVER(PARTITION BY shipperid ORDER BY shippeddate, orderid),
      shippeddate) <= 7 THEN 0 ELSE 1 END AS startflag
  FROM Sales.Orders
  WHERE shippeddate IS NOT NULL
)
SELECT *,
  SUM(startflag) OVER(PARTITION BY shipperid
                      ORDER BY shippeddate, orderid
                      ROWS UNBOUNDED PRECEDING) AS grp
FROM C1;

-- Solution query
WITH C1 AS
(
  SELECT shipperid, shippeddate, orderid,
    CASE WHEN DATEDIFF(day,
      LAG(shippeddate) OVER(PARTITION BY shipperid ORDER BY shippeddate, orderid),
      shippeddate) <= 7 THEN 0 ELSE 1 END AS startflag
  FROM Sales.Orders
  WHERE shippeddate IS NOT NULL
),
C2 AS
(
  SELECT *,
    SUM(startflag) OVER(PARTITION BY shipperid
                        ORDER BY shippeddate, orderid
                        ROWS UNBOUNDED PRECEDING) AS grp
  FROM C1
)
SELECT shipperid,
  MIN(shippeddate) AS fromdate,
  MAX(shippeddate) AS todate,
  COUNT(*) as numorders
FROM C2
GROUP BY shipperid, grp;

DROP INDEX idx_sid_sd_oid ON Sales.Orders;

---------------------------------------------------------------------
-- Pivoting Data
---------------------------------------------------------------------

---------------------------------------------------------------------
-- One-To-One Pivot
---------------------------------------------------------------------

-- Creating and populating the OpenSchema table
USE tempdb;

IF OBJECT_ID(N'dbo.OpenSchema', N'U') IS NOT NULL DROP TABLE dbo.OpenSchema;

CREATE TABLE dbo.OpenSchema
(
  objectid  INT          NOT NULL,
  attribute NVARCHAR(30) NOT NULL,
  value     SQL_VARIANT  NOT NULL, 
  CONSTRAINT PK_OpenSchema PRIMARY KEY (objectid, attribute)
);
GO

INSERT INTO dbo.OpenSchema(objectid, attribute, value) VALUES
  (1, N'attr1', CAST(CAST('ABC'      AS VARCHAR(10)) AS SQL_VARIANT)),
  (1, N'attr2', CAST(CAST(10         AS INT)         AS SQL_VARIANT)),
  (1, N'attr3', CAST(CAST('20130101' AS DATE)        AS SQL_VARIANT)),
  (2, N'attr2', CAST(CAST(12         AS INT)         AS SQL_VARIANT)),
  (2, N'attr3', CAST(CAST('20150101' AS DATE)        AS SQL_VARIANT)),
  (2, N'attr4', CAST(CAST('Y'        AS CHAR(1))     AS SQL_VARIANT)),
  (2, N'attr5', CAST(CAST(13.7       AS NUMERIC(9,3))AS SQL_VARIANT)),
  (3, N'attr1', CAST(CAST('XYZ'      AS VARCHAR(10)) AS SQL_VARIANT)),
  (3, N'attr2', CAST(CAST(20         AS INT)         AS SQL_VARIANT)),
  (3, N'attr3', CAST(CAST('20140101' AS DATE)        AS SQL_VARIANT));

-- Show the contents of the table
SELECT objectid, attribute, value FROM dbo.OpenSchema;
GO

-- Pivoting attributes, without PIVOT operator
SELECT objectid,
  MAX(CASE WHEN attribute = 'attr1' THEN value END) AS attr1,
  MAX(CASE WHEN attribute = 'attr2' THEN value END) AS attr2,
  MAX(CASE WHEN attribute = 'attr3' THEN value END) AS attr3,
  MAX(CASE WHEN attribute = 'attr4' THEN value END) AS attr4,
  MAX(CASE WHEN attribute = 'attr5' THEN value END) AS attr5
FROM dbo.OpenSchema
GROUP BY objectid;

-- Pivoting attributes, using PIVOT operator
SELECT objectid, attr1, attr2, attr3, attr4, attr5
FROM dbo.OpenSchema
  PIVOT(MAX(value) FOR attribute IN(attr1, attr2, attr3, attr4, attr5)) AS P;

-- PIVOT operator, using table expression
SELECT objectid, attr1, attr2, attr3, attr4, attr5
FROM (SELECT objectid, attribute, value FROM dbo.OpenSchema) AS D
  PIVOT(MAX(value) FOR attribute IN(attr1, attr2, attr3, attr4, attr5)) AS P;

---------------------------------------------------------------------
-- Many-To-One Pivot
---------------------------------------------------------------------

-- Sum of values for customers on rows and years on columns
USE TSQLV3;

SELECT custid,
  SUM(CASE WHEN orderyear = 2013 THEN val END) AS [2013],
  SUM(CASE WHEN orderyear = 2014 THEN val END) AS [2014],
  SUM(CASE WHEN orderyear = 2015 THEN val END) AS [2015]
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
GROUP BY custid;

-- With the PIVOT operator
SELECT custid, [2013],[2014],[2015]
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
  PIVOT(SUM(val) FOR orderyear IN([2013],[2014],[2015])) AS P;

-- With matrix table

-- Creating and populating the Matrix table
IF OBJECT_ID(N'dbo.Matrix', N'U') IS NOT NULL DROP TABLE dbo.Matrix;

CREATE TABLE dbo.Matrix
(
  orderyear INT NOT NULL PRIMARY KEY,
  y2013 INT NULL,
  y2014 INT NULL,
  y2015 INT NULL
);
GO

INSERT INTO dbo.Matrix(orderyear, y2013) VALUES(2013, 1);
INSERT INTO dbo.Matrix(orderyear, y2014) VALUES(2014, 1);
INSERT INTO dbo.Matrix(orderyear, y2015) VALUES(2015, 1);

SELECT orderyear, y2013, y2014, y2015 FROM dbo.Matrix;

-- Sum with Matrix
SELECT custid,
  SUM(val*y2013) AS [2013],
  SUM(val*y2014) AS [2014],
  SUM(val*y2015) AS [2015]
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
  INNER JOIN dbo.Matrix AS M ON D.orderyear = M.orderyear
GROUP BY custid;

-- Count without Matrix
SELECT custid,
  SUM(CASE WHEN orderyear = 2013 THEN 1 END) AS [2013],
  SUM(CASE WHEN orderyear = 2014 THEN 1 END) AS [2014],
  SUM(CASE WHEN orderyear = 2015 THEN 1 END) AS [2015]
FROM (SELECT custid, YEAR(orderdate) AS orderyear
      FROM Sales.Orders) AS D
GROUP BY custid;

-- Count with Matrix
SELECT custid,
  SUM(y2013) AS [2013],
  SUM(y2014) AS [2014],
  SUM(y2015) AS [2015]
FROM (SELECT custid, YEAR(orderdate) AS orderyear
      FROM Sales.Orders) AS D
  INNER JOIN dbo.Matrix AS M ON D.orderyear = M.orderyear
GROUP BY custid;

-- Multiple aggregates
SELECT custid,
  SUM(val*y2013) AS sum2013,
  SUM(val*y2014) AS sum2014,
  SUM(val*y2015) AS sum2015,
  AVG(val*y2013) AS avg2013,
  AVG(val*y2014) AS avg2014,
  AVG(val*y2015) AS avg2015,
  SUM(y2013) AS cnt2013,
  SUM(y2014) AS cnt2014,
  SUM(y2015) AS cnt2015
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
  INNER JOIN dbo.Matrix AS M ON D.orderyear = M.orderyear
GROUP BY custid;

---------------------------------------------------------------------
-- UNPIVOT
---------------------------------------------------------------------

IF OBJECT_ID(N'dbo.PvtOrders', N'U') IS NOT NULL DROP TABLE dbo.PvtOrders;

SELECT custid, [2013], [2014], [2015]
INTO dbo.PvtOrders
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
  PIVOT(SUM(val) FOR orderyear IN([2013],[2014],[2015])) AS P;

SELECT custid, [2013], [2014], [2015] FROM dbo.PvtOrders;
GO

---------------------------------------------------------------------
-- Unpivoting with CROSS JOIN and VALUES
---------------------------------------------------------------------

-- Show table contents
SELECT orderyear FROM (VALUES(2013),(2014),(2015)) AS Y(orderyear);

-- Generating copies
SELECT custid, [2013], [2014], [2015], orderyear
FROM dbo.PvtOrders
  CROSS JOIN (VALUES(2013),(2014),(2015)) AS Y(orderyear);

-- Extracting element
SELECT custid, orderyear,
  CASE orderyear
    WHEN 2013 THEN [2013]
    WHEN 2014 THEN [2014]
    WHEN 2015 THEN [2015]
  END AS val
FROM dbo.PvtOrders
  CROSS JOIN (VALUES(2013),(2014),(2015)) AS Y(orderyear);

-- Removing NULLs
SELECT custid, orderyear, val
FROM dbo.PvtOrders
  CROSS JOIN (VALUES(2013),(2014),(2015)) AS Y(orderyear)
  CROSS APPLY (VALUES(CASE orderyear
                        WHEN 2013 THEN [2013]
                        WHEN 2014 THEN [2014]
                        WHEN 2015 THEN [2015]
                      END)) AS A(val)
WHERE val IS NOT NULL;

---------------------------------------------------------------------
-- Unpivoting with CROSS APPLY and VALUES
---------------------------------------------------------------------

-- Single set of columns
SELECT custid, orderyear, val
FROM dbo.PvtOrders
  CROSS APPLY (VALUES(2013, [2013]),(2014, [2014]),(2015, [2015])) AS A(orderyear, val)
WHERE val IS NOT NULL;

-- Multiple sets of columns

-- Sample data
USE tempdb;
IF OBJECT_ID(N'dbo.Sales', N'U') IS NOT NULL DROP TABLE dbo.Sales;
GO

CREATE TABLE dbo.Sales
(
  custid    VARCHAR(10) NOT NULL,
  qty2013   INT   NULL,
  qty2014   INT   NULL,
  qty2015   INT   NULL,
  val2013   MONEY NULL,
  val2014   MONEY NULL,
  val2015   MONEY NULL,
  CONSTRAINT PK_Sales PRIMARY KEY(custid)
);

INSERT INTO dbo.Sales
    (custid, qty2013, qty2014, qty2015, val2013, val2014, val2015)
  VALUES
    ('A', 606,113,781,4632.00,6877.00,4815.00),
    ('B', 243,861,637,2125.00,8413.00,4476.00),
    ('C', 932,117,202,9068.00,342.00,9083.00),
    ('D', 915,833,138,1131.00,9923.00,4164.00),
    ('E', 822,246,870,1907.00,3860.00,7399.00);

-- Solution
SELECT custid, salesyear, qty, val
FROM dbo.Sales
  CROSS APPLY 
    (VALUES(2013, qty2013, val2013),
           (2014, qty2014, val2014),
           (2015, qty2015, val2015)) AS A(salesyear, qty, val)
WHERE qty IS NOT NULL OR val IS NOT NULL;

---------------------------------------------------------------------
-- Using the UNPIVOT operator
---------------------------------------------------------------------

USE TSQLV3;

SELECT custid, orderyear, val
FROM dbo.PvtOrders
  UNPIVOT(val FOR orderyear IN([2013],[2014],[2015])) AS U;

---------------------------------------------------------------------
-- Custom Aggregations
---------------------------------------------------------------------

-- Creating and populating the groups table
USE tempdb;

IF OBJECT_ID(N'dbo.Groups', N'U') IS NOT NULL DROP TABLE dbo.Groups;

CREATE TABLE dbo.Groups
(
  groupid  VARCHAR(10) NOT NULL,
  memberid INT         NOT NULL,
  string   VARCHAR(10) NOT NULL,
  val      INT         NOT NULL,
  PRIMARY KEY (groupid, memberid)
);
GO
    
INSERT INTO dbo.Groups(groupid, memberid, string, val) VALUES
  ('a', 3, 'stra1', 6),
  ('a', 9, 'stra2', 7),
  ('b', 2, 'strb1', 3),
  ('b', 4, 'strb2', 7),
  ('b', 5, 'strb3', 3),
  ('b', 9, 'strb4', 11),
  ('c', 3, 'strc1', 8),
  ('c', 7, 'strc2', 10),
  ('c', 9, 'strc3', 12);

-- Show the contents of the table
SELECT groupid, memberid, string, val FROM dbo.Groups;

---------------------------------------------------------------------
-- Custom Aggregations using Cursors
---------------------------------------------------------------------

DECLARE @Result AS TABLE(groupid VARCHAR(10), string VARCHAR(8000));

DECLARE
  @groupid AS VARCHAR(10), @prvgroupid AS VARCHAR(10),
  @string AS VARCHAR(10), @aggstring AS VARCHAR(8000);

DECLARE C CURSOR FAST_FORWARD FOR
  SELECT groupid, string FROM dbo.Groups ORDER BY groupid, memberid;

OPEN C;

FETCH NEXT FROM C INTO @groupid, @string;

WHILE @@FETCH_STATUS = 0
BEGIN
  IF @groupid <> @prvgroupid
  BEGIN
    INSERT INTO @Result VALUES(@prvgroupid, @aggstring);
    SET @aggstring = NULL;
  END;

  SELECT
    @aggstring = COALESCE(@aggstring + ',', '') + @string,
    @prvgroupid = @groupid;

  FETCH NEXT FROM C INTO @groupid, @string;
END

IF @prvgroupid IS NOT NULL
  INSERT INTO @Result VALUES(@prvgroupid, @aggstring);

CLOSE C;
DEALLOCATE C;

SELECT groupid, string FROM @Result;
GO

---------------------------------------------------------------------
-- Custom Aggregations using Pivoting
---------------------------------------------------------------------

SELECT groupid,
    [1]
  + COALESCE(',' + [2], '')
  + COALESCE(',' + [3], '')
  + COALESCE(',' + [4], '') AS string
FROM (SELECT groupid, string,
        ROW_NUMBER() OVER(PARTITION BY groupid ORDER BY memberid) AS rn
      FROM dbo.Groups AS A) AS D
  PIVOT(MAX(string) FOR rn IN([1],[2],[3],[4])) AS P;

-- Using CONCAT
SELECT groupid,
  CONCAT([1], ','+[2], ','+[3], ','+[4]) AS string
FROM (SELECT groupid, string,
        ROW_NUMBER() OVER(PARTITION BY groupid ORDER BY memberid) AS rn
      FROM dbo.Groups AS A) AS D
  PIVOT(MAX(string) FOR rn IN([1],[2],[3],[4])) AS P;

---------------------------------------------------------------------
-- Specialized Solutions
---------------------------------------------------------------------

-- Need to concatenate the values returned by the following query
SELECT string
FROM dbo.Groups
WHERE groupid = 'b'
ORDER BY memberid;

-- Adding FOR XML PATH
SELECT string AS [text()]
FROM dbo.Groups
WHERE groupid = 'b'
ORDER BY memberid
FOR XML PATH('');

-- Adding TYPE directive
SELECT
  (SELECT string AS [text()]
   FROM dbo.Groups
   WHERE groupid = 'b'
   ORDER BY memberid
   FOR XML PATH(''), TYPE).value('.[1]', 'VARCHAR(MAX)');

-- Add separators
SELECT
  STUFF((SELECT ',' + string AS [text()]
         FROM dbo.Groups
         WHERE groupid = 'b'
         ORDER BY memberid
         FOR XML PATH(''), TYPE).value('.[1]', 'VARCHAR(MAX)'), 1, 1, '');
  
-- String Concatenation with FOR XML
SELECT groupid,
  STUFF((SELECT ',' + string AS [text()]
         FROM dbo.Groups AS G2
         WHERE G2.groupid = G1.groupid
         ORDER BY memberid
         FOR XML PATH(''), TYPE).value('.[1]', 'VARCHAR(MAX)'), 1, 1, '') AS string
FROM dbo.Groups AS G1
GROUP BY groupid;
GO

-- Static PIVOT query
USE TSQLV3;

SELECT custid, [2013],[2014],[2015]
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
  PIVOT(SUM(val) FOR orderyear IN([2013],[2014],[2015])) AS P;

-- Construct the list of spreading values
SELECT
  STUFF(
    (SELECT N',' + QUOTENAME(orderyear) AS [text()]
     FROM (SELECT DISTINCT YEAR(orderdate) AS orderyear
           FROM Sales.Orders) AS Years
     ORDER BY orderyear
     FOR XML PATH(''), TYPE).value('.[1]', 'VARCHAR(MAX)'), 1, 1, '');

-- Dynamic PIVOT
DECLARE
  @cols AS NVARCHAR(1000),
  @sql  AS NVARCHAR(4000);

SET @cols =
  STUFF(
    (SELECT N',' + QUOTENAME(orderyear) AS [text()]
     FROM (SELECT DISTINCT YEAR(orderdate) AS orderyear
           FROM Sales.Orders) AS Years
     ORDER BY orderyear
     FOR XML PATH(''), TYPE).value('.[1]', 'VARCHAR(MAX)'), 1, 1, '')

SET @sql = N'SELECT custid, ' + @cols + N'
FROM (SELECT custid, YEAR(orderdate) AS orderyear, val
      FROM Sales.OrderValues) AS D
  PIVOT(SUM(val) FOR orderyear IN(' + @cols + N')) AS P;';

EXEC sys.sp_executesql @stmt = @sql;
GO

-- String Concatenation with Assignment SELECT

-- Create a table called T1 and populate it with sample data
USE tempdb;
IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;

CREATE TABLE dbo.T1
(
  col1   INT NOT NULL IDENTITY,
  col2   VARCHAR(100) NOT NULL,
  filler BINARY(2000) NULL DEFAULT(0x),
  CONSTRAINT PK_T1 PRIMARY KEY(col1)
);

INSERT INTO dbo.T1(col2)
  SELECT 'String ' + CAST(n AS VARCHAR(10))
  FROM TSQLV3.dbo.GetNums(1, 100) AS Nums;
GO

-- Test 1, with ORDER BY
DECLARE @s AS VARCHAR(MAX);
SET @s = '';

SELECT @s = @s + col2 + ';'
FROM dbo.T1
ORDER BY col1;

PRINT @s;
GO

-- Test 2, with ORDER BY, after adding a covering nonclustered index
CREATE NONCLUSTERED INDEX idx_nc_col2_col1 ON dbo.T1(col2, col1);
GO

DECLARE @s AS VARCHAR(MAX);
SET @s = '';

SELECT @s = @s + col2 + ';'
FROM dbo.T1
ORDER BY col1;

PRINT @s;
GO

-- Aggregate Product
SELECT groupid, ROUND(EXP(SUM(LOG(val))), 0) AS product
FROM dbo.Groups
GROUP BY groupid;

-- Add zeroes and negatives
TRUNCATE TABLE dbo.Groups;

INSERT INTO dbo.Groups(groupid, memberid, string, val) VALUES
  ('a', 3, 'stra1', -6),
  ('a', 9, 'stra2', 7),
  ('b', 2, 'strb1', -3),
  ('b', 4, 'strb2', -7),
  ('b', 5, 'strb3', 3),
  ('b', 9, 'strb4', 11),
  ('c', 3, 'strc1', 8),
  ('c', 7, 'strc2', 0),
  ('c', 9, 'strc3', 12);

-- Query fails
SELECT groupid, ROUND(EXP(SUM(LOG(val))), 0) AS product
FROM dbo.Groups
GROUP BY groupid;

-- Handling zeroes and negatives with CASE expressions
SELECT groupid,
  -- Replace 0 with NULL using NULLIF, apply product to absolute values
  ROUND(EXP(SUM(LOG(ABS(NULLIF(val, 0))))), 0) AS product,
  -- 0 if a 0 exists, 1 if not
  MIN(CASE WHEN val = 0 THEN 0 ELSE 1 END) AS zero,
  -- -1 if odd, 1 if even
  CASE WHEN COUNT(CASE WHEN val < 0 THEN 1 END) % 2 > 0 THEN -1 ELSE 1 END AS negative
FROM dbo.Groups
GROUP BY groupid;

-- All together
SELECT groupid,
  ROUND(EXP(SUM(LOG(ABS(NULLIF(val, 0))))), 0)
  * MIN(CASE WHEN val = 0 THEN 0 ELSE 1 END)
  * CASE WHEN COUNT(CASE WHEN val < 0 THEN 1 END) % 2 > 0 THEN -1 ELSE 1 END AS product
FROM dbo.Groups
GROUP BY groupid;

-- Mathematically
SELECT groupid,
  ROUND(EXP(SUM(LOG(ABS(NULLIF(val, 0))))), 0) AS product,
  MIN(SIGN(ABS(val))) AS zero,
  SUM((1-SIGN(val))/2)%2*-2+1 AS negative
FROM dbo.Groups
GROUP BY groupid;

-- All together
SELECT groupid,
  ROUND(EXP(SUM(LOG(ABS(NULLIF(val, 0))))), 0)
  * MIN(SIGN(ABS(val)))
  * (SUM((1-SIGN(val))/2)%2*-2+1) AS product
FROM dbo.Groups
GROUP BY groupid;

-- Aggregate Mode

-- Solution based on ranking calculations, using a tiebreaker
USE TSQLV3;

WITH C AS
(
  SELECT custid, empid, COUNT(*) AS cnt,
    ROW_NUMBER() OVER(PARTITION BY custid
                      ORDER BY COUNT(*) DESC, empid DESC) AS rn
  FROM Sales.Orders
  GROUP BY custid, empid
)
SELECT custid, empid, cnt
FROM C
WHERE rn = 1;

-- Solution based on ranking calculations, no tiebreaker
WITH C AS
(
  SELECT custid, empid, COUNT(*) AS cnt,
    RANK() OVER(PARTITION BY custid
                ORDER BY COUNT(*) DESC) AS rn
  FROM Sales.Orders
  GROUP BY custid, empid
)
SELECT custid, empid, cnt
FROM C
WHERE rn = 1;

-- Solution based on concatenation
SELECT custid,
  CAST(SUBSTRING(MAX(binval), 5, 4) AS INT) AS empid,
  CAST(SUBSTRING(MAX(binval), 1, 4) AS INT) AS cnt  
FROM (SELECT custid, 
        CAST(COUNT(*) AS BINARY(4)) + CAST(empid AS BINARY(4)) AS binval
      FROM Sales.Orders
      GROUP BY custid, empid) AS D
GROUP BY custid;

---------------------------------------------------------------------
-- Grouping Sets
---------------------------------------------------------------------

-- code to create and populate the orders table
SET NOCOUNT ON;
USE tempdb;

IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;

CREATE TABLE dbo.Orders
(
  orderid   INT        NOT NULL,
  orderdate DATETIME   NOT NULL,
  empid     INT        NOT NULL,
  custid    VARCHAR(5) NOT NULL,
  qty       INT        NOT NULL,
  CONSTRAINT PK_Orders PRIMARY KEY(orderid)
);
GO

INSERT INTO dbo.Orders
  (orderid, orderdate, empid, custid, qty)
VALUES
  (30001, '20120802', 3, 'A', 10),
  (10001, '20121224', 1, 'A', 12),
  (10005, '20121224', 1, 'B', 20),
  (40001, '20130109', 4, 'A', 40),
  (10006, '20130118', 1, 'C', 14),
  (20001, '20130212', 2, 'B', 12),
  (40005, '20140212', 4, 'A', 10),
  (20002, '20140216', 2, 'C', 20),
  (30003, '20140418', 3, 'B', 15),
  (30004, '20120418', 3, 'C', 22),
  (30007, '20120907', 3, 'D', 30);

---------------------------------------------------------------------
-- GROUPING SETS Subclause
---------------------------------------------------------------------

SELECT custid, empid, YEAR(orderdate) AS orderyear, SUM(qty) AS qty
FROM dbo.Orders
GROUP BY GROUPING SETS
(
  ( custid, empid, YEAR(orderdate) ),
  ( custid, YEAR(orderdate)        ),
  ( empid, YEAR(orderdate)         ),
  ()
);

-- Logically equivalent to unifying multiple aggregate queries:
SELECT custid, empid, YEAR(orderdate) AS orderyear, SUM(qty) AS qty
FROM dbo.Orders
GROUP BY custid, empid, YEAR(orderdate)

UNION ALL

SELECT custid, NULL AS empid, YEAR(orderdate) AS orderyear, SUM(qty) AS qty
FROM dbo.Orders
GROUP BY custid, YEAR(orderdate)

UNION ALL

SELECT NULL AS custid, empid, YEAR(orderdate) AS orderyear, SUM(qty) AS qty
FROM dbo.Orders
GROUP BY empid, YEAR(orderdate)

UNION ALL

SELECT NULL AS custid, NULL AS empid, NULL AS orderyear, SUM(qty) AS qty
FROM dbo.Orders;

-- Add computed column and indexes
ALTER TABLE dbo.Orders ADD orderyear AS YEAR(orderdate);
GO
CREATE INDEX idx_eid_oy_cid_i_qty ON dbo.Orders(empid, orderyear, custid) INCLUDE(qty);
CREATE INDEX idx_oy_cid_i_qty ON dbo.Orders(orderyear, custid) INCLUDE(qty);

-- Run query again

---------------------------------------------------------------------
-- CUBE and ROLLUP Subclauses
---------------------------------------------------------------------

---------------------------------------------------------------------
-- CUBE Subclause
---------------------------------------------------------------------

SELECT custid, empid, SUM(qty) AS qty
FROM dbo.Orders
GROUP BY CUBE(custid, empid);

-- Equivalent to:
SELECT custid, empid, SUM(qty) AS qty
FROM dbo.Orders
GROUP BY GROUPING SETS
  ( 
    ( custid, empid ),
    ( custid        ),
    ( empid         ),
    ()
  );

---------------------------------------------------------------------
-- ROLLUP Subclause
---------------------------------------------------------------------

SELECT
  YEAR(orderdate) AS orderyear,
  MONTH(orderdate) AS ordermonth,
  DAY(orderdate) AS orderday,
  SUM(qty) AS qty
FROM dbo.Orders
GROUP BY
  ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate));

-- Equivalent to:
SELECT
  YEAR(orderdate) AS orderyear,
  MONTH(orderdate) AS ordermonth,
  DAY(orderdate) AS orderday,
  SUM(qty) AS qty
FROM dbo.Orders
GROUP BY
  GROUPING SETS
  (
    ( YEAR(orderdate), MONTH(orderdate), DAY(orderdate) ),
    ( YEAR(orderdate), MONTH(orderdate)                 ),
    ( YEAR(orderdate)                                   ),
    ()
  );

---------------------------------------------------------------------
-- Grouping Sets Algebra
---------------------------------------------------------------------

-- Multiplication
SELECT
  custid, 
  empid,
  YEAR(orderdate) AS orderyear,
  MONTH(orderdate) AS ordermonth,
  SUM(qty) AS qty
FROM dbo.Orders
GROUP BY
  GROUPING SETS
  ( 
    ( custid, empid ),
    ( custid        ),
    ( empid         )
  ),
  ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate));

-- Addition
SELECT
  custid, 
  empid,
  YEAR(orderdate) AS orderyear,
  MONTH(orderdate) AS ordermonth,
  SUM(qty) AS qty
FROM dbo.Orders
GROUP BY
  GROUPING SETS
  ( 
    ( custid, empid ),
    ( custid        ),
    ( empid         ),
    ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate))
  );

---------------------------------------------------------------------
-- Materializing grouping sets
---------------------------------------------------------------------

-- GROUPING_ID Function
SELECT 
  GROUPING_ID( custid, empid, YEAR(orderdate), MONTH(orderdate), DAY(orderdate) ) AS grp_id,
  custid, empid,
  YEAR(orderdate) AS orderyear,
  MONTH(orderdate) AS ordermonth,
  DAY(orderdate) AS orderday,
  SUM(qty) AS qty
FROM dbo.Orders
GROUP BY
  CUBE(custid, empid),
  ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate));

-- Full processing
USE tempdb;
IF OBJECT_ID(N'dbo.MyGroupingSets', N'U') IS NOT NULL  DROP TABLE dbo.MyGroupingSets;
GO

SELECT 
  GROUPING_ID(
    custid, empid,
    YEAR(orderdate), MONTH(orderdate), DAY(orderdate) ) AS grp_id,
  custid, empid,
  YEAR(orderdate) AS orderyear,
  MONTH(orderdate) AS ordermonth,
  DAY(orderdate) AS orderday,
  SUM(qty) AS qty
INTO dbo.MyGroupingSets
FROM dbo.Orders
GROUP BY
  CUBE(custid, empid),
  ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate));

CREATE UNIQUE CLUSTERED INDEX idx_cl_groupingsets
  ON dbo.MyGroupingSets(grp_id, custid, empid, orderyear, ordermonth, orderday);
GO

-- Query
SELECT *
FROM dbo.MyGroupingSets
WHERE grp_id = 9;

-- New order activity added in April 19, 2014
INSERT INTO dbo.Orders
  (orderid, orderdate, empid, custid, qty)
VALUES
  (50001, '20140419', 1, 'A', 10),
  (50002, '20140419', 1, 'B', 30),
  (50003, '20140419', 2, 'A', 20),
  (50004, '20140419', 2, 'B',  5),
  (50005, '20140419', 3, 'A', 15);
GO

-- Incremental update
WITH LastDay AS
(
  SELECT 
    GROUPING_ID(
      custid, empid,
      YEAR(orderdate), MONTH(orderdate), DAY(orderdate) ) AS grp_id,
    custid, empid,
    YEAR(orderdate) AS orderyear,
    MONTH(orderdate) AS ordermonth,
    DAY(orderdate) AS orderday,
    SUM(qty) AS qty
  FROM dbo.Orders
  WHERE orderdate = '20140419'
  GROUP BY
    CUBE(custid, empid),
    ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate))
)
MERGE INTO dbo.MyGroupingSets AS TGT
USING LastDay AS SRC
  ON EXISTS(
  SELECT SRC.grp_id, SRC.orderyear, SRC.ordermonth, SRC.orderday, SRC.custid, SRC.empid
  INTERSECT
  SELECT TGT.grp_id, TGT.orderyear, TGT.ordermonth, TGT.orderday, TGT.custid, TGT.empid)
WHEN MATCHED THEN
  UPDATE SET
    TGT.qty += SRC.qty
WHEN NOT MATCHED THEN
  INSERT (grp_id, custid, empid, orderyear, ordermonth, orderday)
  VALUES (SRC.grp_id, SRC.custid, SRC.empid, SRC.orderyear, SRC.ordermonth, SRC.orderday);

---------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------

SELECT 
  YEAR(orderdate)  AS orderyear,
  MONTH(orderdate) AS ordermonth,
  DAY(orderdate)   AS orderday,
  SUM(qty)         AS totalqty
FROM dbo.Orders
GROUP BY
  ROLLUP(YEAR(orderdate), MONTH(orderdate), DAY(orderdate))
ORDER BY
  GROUPING(YEAR(orderdate)) , YEAR(orderdate),
  GROUPING(MONTH(orderdate)), MONTH(orderdate),
  GROUPING(DAY(orderdate))  , DAY(orderdate);
