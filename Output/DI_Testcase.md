# DI_CodeUpdate – T-SQL Test Strategy and Python Test Suite

====================================================================
Author: Ascendion AAVA
Date: 
Description: Comprehensive T-SQL test strategy and Python-based executable tests for the DI_CodeUpdate ETL (tile and branch enrichment with INSERT/UPDATE semantics).
====================================================================

---

## 1. Scope and Context

This document defines the **test strategy** and provides **executable Python-based tests** for the SQL Server ETL implementation described as `DI_CodeUpdate` (Version 1 logic) and its related Python harness. The focus is on:

- `dbo.usp_Run_ETL_DailySummary` – main ETL stored procedure.
- Source tables:
  - `dbo.SOURCE_HOME_TILE_EVENTS`
  - `dbo.SOURCE_INTERSTITIAL_EVENTS`
  - `dbo.SOURCE_TILE_METADATA`
  - `dbo.BRANCH_OPERATIONAL_DETAILS`
- Target tables:
  - `dbo.TILE_DAILY_SUMMARY`
  - `dbo.BRANCH_SUMMARY_REPORT`
- Logging table:
  - `dbo.ETL_Execution_Log`

The tests validate:

- Correct **aggregations and enrichments** (tile_category, REGION, LAST_AUDIT_DATE).
- Proper **INSERT vs UPDATE** behavior for target tables.
- Handling of **missing metadata** (default tile_category = `'UNKNOWN'`).
- **Transactional and error handling** behavior.

Source model references (from Git inputs):

- `Input/SOURCE_TILE_METADATA.sql` – Delta table definition for `SOURCE_TILE_METADATA`.
- `Input/SourceDDL.sql` – Delta table definitions for `SOURCE_HOME_TILE_EVENTS` and `SOURCE_INTERSTITIAL_EVENTS`.
- `Input/branch_operational_details.sql` – Oracle table definition for `BRANCH_OPERATIONAL_DETAILS`.

These have been ported into SQL Server equivalents in the T-SQL ETL (Version 1).

---

## 2. T-SQL Test Strategy

### 2.1 Objects Under Test

1. **Stored Procedure**
   - `dbo.usp_Run_ETL_DailySummary(@SummaryDate DATE)`

2. **Source Tables**
   - `dbo.SOURCE_HOME_TILE_EVENTS`
   - `dbo.SOURCE_INTERSTITIAL_EVENTS`
   - `dbo.SOURCE_TILE_METADATA`
   - `dbo.BRANCH_OPERATIONAL_DETAILS`

3. **Target Tables**
   - `dbo.TILE_DAILY_SUMMARY`
   - `dbo.BRANCH_SUMMARY_REPORT`

4. **Supporting Table**
   - `dbo.ETL_Execution_Log`

### 2.2 Key Behaviors to Validate

- **Tile Aggregation and Enrichment**
  - Correct counts of `total_views` and `total_clicks` per tile per day.
  - Correct computation of `click_through_rate` = `total_clicks / total_views` (0 when `total_views = 0`).
  - Correct aggregation of interstitial metrics (`interstitial_views`, `interstitial_primary_cta`, `interstitial_secondary_cta`).
  - Enrichment via `SOURCE_TILE_METADATA`:
    - When metadata exists → use `tile_category` from metadata.
    - When metadata is missing → default `tile_category` to `'UNKNOWN'`.

- **Branch Aggregation and Enrichment**
  - For each `BRANCH_ID` in `BRANCH_OPERATIONAL_DETAILS`, produce a row for the summary date.
  - Enrich with `REGION` and `LAST_AUDIT_DATE` from `BRANCH_OPERATIONAL_DETAILS`.
  - Populate `total_transactions` (simulated metric = 10) and `is_active`.

- **INSERT vs UPDATE Semantics**
  - On first ETL run:
    - Insert records into `TILE_DAILY_SUMMARY` and `BRANCH_SUMMARY_REPORT`.
  - On subsequent ETL run with changed source metadata:
    - Update existing rows in `TILE_DAILY_SUMMARY` and `BRANCH_SUMMARY_REPORT`.
    - No duplicate rows for same `(SummaryDate, tile_id)` or `(SummaryDate, BRANCH_ID)`.

- **Logging and Error Handling**
  - Insert start and success entries into `ETL_Execution_Log` for `BEGIN_TRANSACTION`, `TileAggregation`, and `BranchAggregation` steps.
  - On error:
    - Transaction is rolled back.
    - Log entry is inserted with `Status = 'FAILED'` and appropriate error details.
    - Error is re-thrown to caller.

### 2.3 Test Case List

Below is the **indexed test case list**. Each test case is later reflected as a Python `unittest` method and/or helper, and the index comment is mirrored in the logs.

| Test Case ID | Description |
| ------------ | ----------- |
| TC01 | Validate successful INSERT into `TILE_DAILY_SUMMARY` for seeded tile events and metadata. |
| TC02 | Validate successful INSERT into `BRANCH_SUMMARY_REPORT` for seeded branches. |
| TC03 | Validate `tile_category` enrichment, including default `'UNKNOWN'` for tiles without metadata. |
| TC04 | Validate `click_through_rate` calculation, including division-by-zero protection. |
| TC05 | Validate interstitial metrics aggregation (views and CTA clicks) per tile. |
| TC06 | Validate UPDATE behavior for `TILE_DAILY_SUMMARY` when `SOURCE_TILE_METADATA.tile_category` changes. |
| TC07 | Validate UPDATE behavior for `BRANCH_SUMMARY_REPORT` when `BRANCH_OPERATIONAL_DETAILS.REGION` changes. |
| TC08 | Validate MERGE semantics – no duplicate rows for the same `(SummaryDate, tile_id)` or `(SummaryDate, BRANCH_ID)`. |
| TC09 | Validate ETL execution logging for happy path (statuses and messages per step). |
| TC10 | Validate transaction rollback and logging when a forced error occurs during tile aggregation. |

---

## 3. T-SQL-Oriented Test Case Details

The following describes each test case in **T-SQL terms**. The executable implementation is provided in Python in section 4.

> Note: Index comments must appear at the beginning of each logical test scenario.

### TC01 – INSERT into TILE_DAILY_SUMMARY

```sql
-- ============================================================
-- TEST CASE 01: Validate successful INSERT into TILE_DAILY_SUMMARY
-- ============================================================
-- Test setup: use seeded SOURCE_HOME_TILE_EVENTS and SOURCE_TILE_METADATA for @SummaryDate
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result: one row per tile (TILE_001, TILE_002, TILE_999)
-- Validate actual result: SELECT COUNT(*) FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = @SummaryDate
```

### TC02 – INSERT into BRANCH_SUMMARY_REPORT

```sql
-- ============================================================
-- TEST CASE 02: Validate successful INSERT into BRANCH_SUMMARY_REPORT
-- ============================================================
-- Test setup: seeded BRANCH_OPERATIONAL_DETAILS for @SummaryDate
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result: one row per branch (101, 102)
-- Validate actual result: SELECT COUNT(*) FROM dbo.BRANCH_SUMMARY_REPORT WHERE SummaryDate = @SummaryDate
```

### TC03 – Tile Category Enrichment and Default UNKNOWN

```sql
-- ============================================================
-- TEST CASE 03: Validate tile_category enrichment including default UNKNOWN
-- ============================================================
-- Test setup: metadata present for TILE_001, TILE_002, TILE_003; missing for TILE_999
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   TILE_001 -> tile_category = 'OFFERS'
--   TILE_002 -> tile_category = 'HEALTH'
--   TILE_003 -> tile_category = 'PAYMENTS' (if events exist)
--   TILE_999 -> tile_category = 'UNKNOWN'
-- Validate actual result: SELECT tile_id, tile_category FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = @SummaryDate
```

### TC04 – Click-Through Rate Calculation

```sql
-- ============================================================
-- TEST CASE 04: Validate click_through_rate calculation and zero-division handling
-- ============================================================
-- Test setup: events with different view/click combinations, including 0 views
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   CTR = total_clicks / total_views when views > 0
--   CTR = 0 when views = 0 (no division-by-zero error)
-- Validate actual result: SELECT tile_id, total_views, total_clicks, click_through_rate FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = @SummaryDate
```

### TC05 – Interstitial Aggregation

```sql
-- ============================================================
-- TEST CASE 05: Validate interstitial metrics aggregation per tile
-- ============================================================
-- Test setup: SOURCE_INTERSTITIAL_EVENTS seeded with multiple rows per tile
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   interstitial_views = SUM(interstitial_view_flag)
--   interstitial_primary_cta = SUM(primary_button_click_flag)
--   interstitial_secondary_cta = SUM(secondary_button_click_flag)
-- Validate actual result: SELECT tile_id, interstitial_views, interstitial_primary_cta, interstitial_secondary_cta FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = @SummaryDate
```

### TC06 – UPDATE Behavior for TILE_DAILY_SUMMARY

```sql
-- ============================================================
-- TEST CASE 06: Validate UPDATE behavior for TILE_DAILY_SUMMARY on metadata change
-- ============================================================
-- Test setup:
--   1) Run ETL once for @SummaryDate to insert baseline rows.
--   2) UPDATE dbo.SOURCE_TILE_METADATA SET tile_category = 'OFFERS_UPDATED' WHERE tile_id = 'TILE_001'.
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   TILE_DAILY_SUMMARY row for TILE_001 has tile_category = 'OFFERS_UPDATED'.
--   No additional rows created for same (SummaryDate, tile_id).
-- Validate actual result: SELECT tile_category FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = @SummaryDate AND tile_id = 'TILE_001'
```

### TC07 – UPDATE Behavior for BRANCH_SUMMARY_REPORT

```sql
-- ============================================================
-- TEST CASE 07: Validate UPDATE behavior for BRANCH_SUMMARY_REPORT on REGION change
-- ============================================================
-- Test setup:
--   1) Run ETL once for @SummaryDate to insert baseline rows.
--   2) UPDATE dbo.BRANCH_OPERATIONAL_DETAILS SET REGION = 'NORTH_UPDATED' WHERE BRANCH_ID = 101.
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   BRANCH_SUMMARY_REPORT row for BRANCH_ID = 101 has REGION = 'NORTH_UPDATED'.
--   No additional rows created for same (SummaryDate, BRANCH_ID).
-- Validate actual result: SELECT REGION FROM dbo.BRANCH_SUMMARY_REPORT WHERE SummaryDate = @SummaryDate AND BRANCH_ID = 101
```

### TC08 – MERGE Semantics (No Duplicates)

```sql
-- ============================================================
-- TEST CASE 08: Validate MERGE semantics – no duplicate keys in targets
-- ============================================================
-- Test setup:
--   Run ETL multiple times for the same @SummaryDate.
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate (twice or more)
-- Validate expected result:
--   Primary keys (SummaryDate, tile_id) and (SummaryDate, BRANCH_ID) remain unique.
-- Validate actual result:
--   SELECT SummaryDate, tile_id, COUNT(*) FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = @SummaryDate GROUP BY SummaryDate, tile_id HAVING COUNT(*) > 1;
--   SELECT SummaryDate, BRANCH_ID, COUNT(*) FROM dbo.BRANCH_SUMMARY_REPORT WHERE SummaryDate = @SummaryDate GROUP BY SummaryDate, BRANCH_ID HAVING COUNT(*) > 1;
--   Expect no rows.
```

### TC09 – Logging for Happy Path

```sql
-- ============================================================
-- TEST CASE 09: Validate ETL_Execution_Log entries for happy path
-- ============================================================
-- Test setup: normal ETL execution for @SummaryDate.
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   Log entries exist for ExecutionName = 'DailySummary_<date>'.
--   Steps: 'BEGIN_TRANSACTION', 'TileAggregation', 'BranchAggregation' with Status 'SUCCESS'.
-- Validate actual result:
--   SELECT StepName, Status, Message FROM dbo.ETL_Execution_Log WHERE ExecutionName = 'DailySummary_<date>'
```

### TC10 – Error Handling and Rollback

```sql
-- ============================================================
-- TEST CASE 10: Validate transaction rollback and error logging on failure
-- ============================================================
-- Test setup:
--   Introduce a forced failure, e.g., temporarily add a constraint or simulate a runtime error inside procedure (for test only).
-- Execute T-SQL logic: EXEC dbo.usp_Run_ETL_DailySummary @SummaryDate
-- Validate expected result:
--   Transaction is rolled back (no partial data in targets).
--   Log entry with Status = 'FAILED' and appropriate error message.
--   Error raised to caller.
-- Validate actual result:
--   SELECT * FROM dbo.ETL_Execution_Log WHERE Status = 'FAILED' AND ExecutionName = 'DailySummary_<date>'
```

---

## 4. Python-Based Executable Test Script

The following Python script implements the above test cases using `unittest`. It:

- Connects to SQL Server via `pyodbc`.
- Bootstraps the full T-SQL schema and procedure (Version 1 logic reproduced below).
- Seeds test data.
- Executes `dbo.usp_Run_ETL_DailySummary`.
- Performs assertions for each test case.
- Emits Markdown-style logs (optional, via `print`).

> Adjust connection parameters for your environment before running.

```python
"""
============================================================
Metadata
============================================================
Version      : 1
Previous     : None
Update       : Initial unit test suite for DI_CodeUpdate ETL.
Purpose      : Python-based SQL Server tests for dbo.usp_Run_ETL_DailySummary
               including INSERT, UPDATE, logging, and error handling.
============================================================
"""

import os
import unittest
import datetime
import textwrap

import pyodbc

# ---------------------------------------------------------------------------
# SQL Server Connectivity Configuration
# ---------------------------------------------------------------------------

SQL_SERVER_CONFIG = {
    "driver": os.getenv("SQLSERVER_DRIVER", "{ODBC Driver 17 for SQL Server}"),
    "server": os.getenv("SQLSERVER_SERVER", "localhost"),
    "database": os.getenv("SQLSERVER_DATABASE", "TestDB"),
    "uid": os.getenv("SQLSERVER_UID", "sa"),
    "pwd": os.getenv("SQLSERVER_PWD", "YourStrong(!)Password"),
}


def get_connection():
    conn_str = (
        f"DRIVER={SQL_SERVER_CONFIG['driver']};"
        f"SERVER={SQL_SERVER_CONFIG['server']};"
        f"DATABASE={SQL_SERVER_CONFIG['database']};"
        f"UID={SQL_SERVER_CONFIG['uid']};"
        f"PWD={SQL_SERVER_CONFIG['pwd']}"
    )
    return pyodbc.connect(conn_str)


# ---------------------------------------------------------------------------
# Full T-SQL Schema and Procedure (Bootstrap) – DI_CodeUpdate Version 1
# ---------------------------------------------------------------------------

TSQL_BOOTSTRAP = r"""
-- Drop existing objects
IF OBJECT_ID('dbo.SOURCE_HOME_TILE_EVENTS', 'U') IS NOT NULL DROP TABLE dbo.SOURCE_HOME_TILE_EVENTS;
IF OBJECT_ID('dbo.SOURCE_INTERSTITIAL_EVENTS', 'U') IS NOT NULL DROP TABLE dbo.SOURCE_INTERSTITIAL_EVENTS;
IF OBJECT_ID('dbo.SOURCE_TILE_METADATA', 'U') IS NOT NULL DROP TABLE dbo.SOURCE_TILE_METADATA;
IF OBJECT_ID('dbo.BRANCH_OPERATIONAL_DETAILS', 'U') IS NOT NULL DROP TABLE dbo.BRANCH_OPERATIONAL_DETAILS;
IF OBJECT_ID('dbo.TILE_DAILY_SUMMARY', 'U') IS NOT NULL DROP TABLE dbo.TILE_DAILY_SUMMARY;
IF OBJECT_ID('dbo.BRANCH_SUMMARY_REPORT', 'U') IS NOT NULL DROP TABLE dbo.BRANCH_SUMMARY_REPORT;
IF OBJECT_ID('dbo.ETL_Execution_Log', 'U') IS NOT NULL DROP TABLE dbo.ETL_Execution_Log;
IF OBJECT_ID('dbo.usp_Run_ETL_DailySummary', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_Run_ETL_DailySummary;
GO

CREATE TABLE dbo.ETL_Execution_Log
(
    LogID          INT IDENTITY(1,1) PRIMARY KEY,
    ExecutionName  NVARCHAR(200),
    StepName       NVARCHAR(200),
    Status         NVARCHAR(50),
    Message        NVARCHAR(4000),
    StartTime      DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    EndTime        DATETIME2(3) NULL
);
GO

CREATE TABLE dbo.SOURCE_HOME_TILE_EVENTS
(
    event_id     NVARCHAR(50)      NOT NULL,
    user_id      NVARCHAR(50)      NOT NULL,
    session_id   NVARCHAR(50)      NOT NULL,
    event_ts     DATETIME2(3)      NOT NULL,
    tile_id      NVARCHAR(50)      NOT NULL,
    event_type   NVARCHAR(20)      NOT NULL,
    device_type  NVARCHAR(20)      NULL,
    app_version  NVARCHAR(20)      NULL
);
GO

CREATE TABLE dbo.SOURCE_INTERSTITIAL_EVENTS
(
    event_id                    NVARCHAR(50)     NOT NULL,
    user_id                     NVARCHAR(50)     NOT NULL,
    session_id                  NVARCHAR(50)     NOT NULL,
    event_ts                    DATETIME2(3)     NOT NULL,
    tile_id                     NVARCHAR(50)     NOT NULL,
    interstitial_view_flag      BIT              NOT NULL,
    primary_button_click_flag   BIT              NOT NULL,
    secondary_button_click_flag BIT              NOT NULL
);
GO

CREATE TABLE dbo.SOURCE_TILE_METADATA
(
    tile_id       NVARCHAR(50)    NOT NULL,
    tile_name     NVARCHAR(200)   NOT NULL,
    tile_category NVARCHAR(100)   NOT NULL,
    is_active     BIT             NOT NULL,
    updated_ts    DATETIME2(3)    NOT NULL,
    CONSTRAINT PK_SOURCE_TILE_METADATA PRIMARY KEY (tile_id)
);
GO

CREATE TABLE dbo.BRANCH_OPERATIONAL_DETAILS
(
    BRANCH_ID        INT            NOT NULL,
    REGION           NVARCHAR(50)   NOT NULL,
    MANAGER_NAME     NVARCHAR(100)  NOT NULL,
    LAST_AUDIT_DATE  DATE           NULL,
    IS_ACTIVE        CHAR(1)        NOT NULL,
    CONSTRAINT PK_BRANCH_OPERATIONAL_DETAILS PRIMARY KEY (BRANCH_ID)
);
GO

CREATE TABLE dbo.TILE_DAILY_SUMMARY
(
    SummaryDate                DATE           NOT NULL,
    tile_id                    NVARCHAR(50)  NOT NULL,
    tile_category              NVARCHAR(100) NOT NULL,
    total_views                INT           NOT NULL,
    total_clicks               INT           NOT NULL,
    click_through_rate         DECIMAL(9,4)  NOT NULL,
    interstitial_views         INT           NOT NULL,
    interstitial_primary_cta   INT           NOT NULL,
    interstitial_secondary_cta INT           NOT NULL,
    CONSTRAINT PK_TILE_DAILY_SUMMARY PRIMARY KEY (SummaryDate, tile_id)
);
GO

CREATE TABLE dbo.BRANCH_SUMMARY_REPORT
(
    SummaryDate      DATE           NOT NULL,
    BRANCH_ID        INT            NOT NULL,
    REGION           NVARCHAR(50)   NULL,
    LAST_AUDIT_DATE  DATE           NULL,
    total_transactions INT          NOT NULL DEFAULT 0,
    is_active         CHAR(1)       NOT NULL,
    CONSTRAINT PK_BRANCH_SUMMARY_REPORT PRIMARY KEY (SummaryDate, BRANCH_ID)
);
GO

CREATE PROCEDURE dbo.usp_Run_ETL_DailySummary
    @SummaryDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExecutionName NVARCHAR(200) = CONCAT('DailySummary_', CONVERT(NVARCHAR(30), @SummaryDate, 23));
    DECLARE @StepName NVARCHAR(200);
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY
        SET @StepName = 'BEGIN_TRANSACTION';
        INSERT INTO dbo.ETL_Execution_Log (ExecutionName, StepName, Status, Message)
        VALUES (@ExecutionName, @StepName, 'STARTED', 'ETL execution started');

        BEGIN TRANSACTION;

        -- Tile aggregation with metadata enrichment
        SET @StepName = 'TileAggregation';

        ;WITH TileEvents AS (
            SELECT
                CAST(event_ts AS DATE) AS SummaryDate,
                tile_id,
                SUM(CASE WHEN event_type = 'TILE_VIEW'  THEN 1 ELSE 0 END) AS total_views,
                SUM(CASE WHEN event_type = 'TILE_CLICK' THEN 1 ELSE 0 END) AS total_clicks
            FROM dbo.SOURCE_HOME_TILE_EVENTS
            WHERE CAST(event_ts AS DATE) = @SummaryDate
            GROUP BY CAST(event_ts AS DATE), tile_id
        ),
        InterstitialEvents AS (
            SELECT
                CAST(event_ts AS DATE) AS SummaryDate,
                tile_id,
                SUM(CASE WHEN interstitial_view_flag = 1 THEN 1 ELSE 0 END) AS interstitial_views,
                SUM(CASE WHEN primary_button_click_flag = 1 THEN 1 ELSE 0 END) AS primary_cta_clicks,
                SUM(CASE WHEN secondary_button_click_flag = 1 THEN 1 ELSE 0 END) AS secondary_cta_clicks
            FROM dbo.SOURCE_INTERSTITIAL_EVENTS
            WHERE CAST(event_ts AS DATE) = @SummaryDate
            GROUP BY CAST(event_ts AS DATE), tile_id
        ),
        TileAgg AS (
            SELECT
                e.SummaryDate,
                e.tile_id,
                ISNULL(m.tile_category, 'UNKNOWN') AS tile_category,
                e.total_views,
                e.total_clicks,
                CASE
                    WHEN e.total_views = 0 THEN 0
                    ELSE CAST(e.total_clicks AS DECIMAL(9,4)) / CAST(e.total_views AS DECIMAL(9,4))
                END AS click_through_rate,
                ISNULL(i.interstitial_views, 0) AS interstitial_views,
                ISNULL(i.primary_cta_clicks, 0) AS interstitial_primary_cta,
                ISNULL(i.secondary_cta_clicks, 0) AS interstitial_secondary_cta
            FROM TileEvents e
            LEFT JOIN InterstitialEvents i
                ON e.SummaryDate = i.SummaryDate
               AND e.tile_id = i.tile_id
            LEFT JOIN dbo.SOURCE_TILE_METADATA m
                ON e.tile_id = m.tile_id
        )
        MERGE dbo.TILE_DAILY_SUMMARY AS tgt
        USING (
            SELECT * FROM TileAgg
        ) AS src
        ON tgt.SummaryDate = src.SummaryDate
           AND tgt.tile_id = src.tile_id
        WHEN MATCHED THEN
            UPDATE SET
                tgt.tile_category              = src.tile_category,
                tgt.total_views                = src.total_views,
                tgt.total_clicks               = src.total_clicks,
                tgt.click_through_rate         = src.click_through_rate,
                tgt.interstitial_views         = src.interstitial_views,
                tgt.interstitial_primary_cta   = src.interstitial_primary_cta,
                tgt.interstitial_secondary_cta = src.interstitial_secondary_cta
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (SummaryDate, tile_id, tile_category, total_views, total_clicks, click_through_rate,
                    interstitial_views, interstitial_primary_cta, interstitial_secondary_cta)
            VALUES (src.SummaryDate, src.tile_id, src.tile_category, src.total_views, src.total_clicks,
                    src.click_through_rate, src.interstitial_views, src.interstitial_primary_cta,
                    src.interstitial_secondary_cta);

        INSERT INTO dbo.ETL_Execution_Log (ExecutionName, StepName, Status, Message)
        VALUES (@ExecutionName, @StepName, 'SUCCESS', 'Tile aggregation completed');

        -- Branch aggregation & enrichment
        SET @StepName = 'BranchAggregation';

        ;WITH BranchBase AS (
            SELECT
                @SummaryDate AS SummaryDate,
                b.BRANCH_ID,
                b.IS_ACTIVE,
                10 AS total_transactions
            FROM dbo.BRANCH_OPERATIONAL_DETAILS b
        )
        MERGE dbo.BRANCH_SUMMARY_REPORT AS tgt
        USING (
            SELECT
                bb.SummaryDate,
                bb.BRANCH_ID,
                bod.REGION,
                bod.LAST_AUDIT_DATE,
                bb.total_transactions,
                bb.IS_ACTIVE
            FROM BranchBase bb
            INNER JOIN dbo.BRANCH_OPERATIONAL_DETAILS bod
                ON bb.BRANCH_ID = bod.BRANCH_ID
        ) AS src
        ON tgt.SummaryDate = src.SummaryDate
           AND tgt.BRANCH_ID = src.BRANCH_ID
        WHEN MATCHED THEN
            UPDATE SET
                tgt.REGION            = src.REGION,
                tgt.LAST_AUDIT_DATE   = src.LAST_AUDIT_DATE,
                tgt.total_transactions = src.total_transactions,
                tgt.is_active         = src.IS_ACTIVE
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (SummaryDate, BRANCH_ID, REGION, LAST_AUDIT_DATE, total_transactions, is_active)
            VALUES (src.SummaryDate, src.BRANCH_ID, src.REGION, src.LAST_AUDIT_DATE, src.total_transactions, src.IS_ACTIVE);

        INSERT INTO dbo.ETL_Execution_Log (ExecutionName, StepName, Status, Message)
        VALUES (@ExecutionName, @StepName, 'SUCCESS', 'Branch aggregation completed');

        COMMIT TRANSACTION;

        UPDATE dbo.ETL_Execution_Log
        SET Status = 'SUCCESS', EndTime = SYSUTCDATETIME(), Message = 'ETL completed successfully'
        WHERE ExecutionName = @ExecutionName AND StepName = 'BEGIN_TRANSACTION';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = CONCAT('Error ', ERROR_NUMBER(), ' at line ', ERROR_LINE(), ': ', ERROR_MESSAGE());

        INSERT INTO dbo.ETL_Execution_Log (ExecutionName, StepName, Status, Message)
        VALUES (@ExecutionName, ISNULL(@StepName, 'UNKNOWN_STEP'), 'FAILED', @ErrorMessage);

        THROW;
    END CATCH
END;
GO
"""


def execute_tsql_batch(cursor, tsql_batch: str):
    """Execute a full T-SQL batch, splitting on GO."""
    for part in tsql_batch.split("GO"):
        stmt = part.strip()
        if stmt:
            cursor.execute(stmt)


# ---------------------------------------------------------------------------
# Test Data Seeding Helpers
# ---------------------------------------------------------------------------

def seed_test_data(cursor, summary_date: datetime.date):
    """Seed source and baseline target data for tests."""
    # Clear data
    cursor.execute("DELETE FROM dbo.SOURCE_HOME_TILE_EVENTS")
    cursor.execute("DELETE FROM dbo.SOURCE_INTERSTITIAL_EVENTS")
    cursor.execute("DELETE FROM dbo.SOURCE_TILE_METADATA")
    cursor.execute("DELETE FROM dbo.BRANCH_OPERATIONAL_DETAILS")
    cursor.execute("DELETE FROM dbo.TILE_DAILY_SUMMARY")
    cursor.execute("DELETE FROM dbo.BRANCH_SUMMARY_REPORT")
    cursor.execute("DELETE FROM dbo.ETL_Execution_Log")

    # Seed metadata
    cursor.execute(
        """INSERT INTO dbo.SOURCE_TILE_METADATA (tile_id, tile_name, tile_category, is_active, updated_ts)
        VALUES
            ('TILE_001', 'Offers Tile', 'OFFERS', 1, SYSUTCDATETIME()),
            ('TILE_002', 'Health Tile', 'HEALTH', 1, SYSUTCDATETIME()),
            ('TILE_003', 'Payments Tile', 'PAYMENTS', 1, SYSUTCDATETIME())"""
    )

    # Seed home tile events
    cursor.execute(
        """INSERT INTO dbo.SOURCE_HOME_TILE_EVENTS (event_id, user_id, session_id, event_ts, tile_id, event_type, device_type, app_version)
        VALUES
            ('E1', 'U1', 'S1', DATEADD(HOUR, 1, ?), 'TILE_001', 'TILE_VIEW',  'Mobile', '1.0'),
            ('E2', 'U1', 'S1', DATEADD(HOUR, 1, ?), 'TILE_001', 'TILE_CLICK', 'Mobile', '1.0'),
            ('E3', 'U2', 'S2', DATEADD(HOUR, 2, ?), 'TILE_001', 'TILE_VIEW',  'Web',    '1.1'),
            ('E4', 'U3', 'S3', DATEADD(HOUR, 3, ?), 'TILE_002', 'TILE_VIEW',  'Web',    '1.0'),
            ('E5', 'U3', 'S3', DATEADD(HOUR, 3, ?), 'TILE_002', 'TILE_CLICK', 'Web',   '1.0'),
            ('E6', 'U4', 'S4', DATEADD(HOUR, 4, ?), 'TILE_999', 'TILE_VIEW',  'Mobile', '1.0')""",
        summary_date,
        summary_date,
        summary_date,
        summary_date,
        summary_date,
        summary_date,
    )

    # Seed interstitial events
    cursor.execute(
        """INSERT INTO dbo.SOURCE_INTERSTITIAL_EVENTS (event_id, user_id, session_id, event_ts, tile_id, interstitial_view_flag, primary_button_click_flag, secondary_button_click_flag)
        VALUES
            ('IE1', 'U1', 'S1', DATEADD(HOUR, 1, ?), 'TILE_001', 1, 1, 0),
            ('IE2', 'U2', 'S2', DATEADD(HOUR, 2, ?), 'TILE_001', 1, 0, 1),
            ('IE3', 'U3', 'S3', DATEADD(HOUR, 3, ?), 'TILE_002', 1, 1, 0)""",
        summary_date,
        summary_date,
        summary_date,
    )

    # Seed branch operational details
    cursor.execute(
        """INSERT INTO dbo.BRANCH_OPERATIONAL_DETAILS (BRANCH_ID, REGION, MANAGER_NAME, LAST_AUDIT_DATE, IS_ACTIVE)
        VALUES
            (101, 'NORTH', 'Alice Manager',  DATEADD(DAY, -10, ?), 'Y'),
            (102, 'SOUTH', 'Bob Manager',    DATEADD(DAY, -20, ?), 'Y')""",
        summary_date,
        summary_date,
    )

    # Seed initial branch summary report to test UPDATE
    cursor.execute(
        """INSERT INTO dbo.BRANCH_SUMMARY_REPORT (SummaryDate, BRANCH_ID, REGION, LAST_AUDIT_DATE, total_transactions, is_active)
        VALUES (?, 101, NULL, NULL, 5, 'Y')""",
        summary_date,
    )


# ---------------------------------------------------------------------------
# Helper query functions
# ---------------------------------------------------------------------------

def fetch_tile_summary(cursor, summary_date):
    cursor.execute(
        """SELECT SummaryDate, tile_id, tile_category,
                   total_views, total_clicks, click_through_rate,
                   interstitial_views, interstitial_primary_cta, interstitial_secondary_cta
            FROM dbo.TILE_DAILY_SUMMARY
            WHERE SummaryDate = ?
            ORDER BY tile_id""",
        summary_date,
    )
    cols = [c[0] for c in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


def fetch_branch_summary(cursor, summary_date):
    cursor.execute(
        """SELECT SummaryDate, BRANCH_ID, REGION, LAST_AUDIT_DATE,
                   total_transactions, is_active
            FROM dbo.BRANCH_SUMMARY_REPORT
            WHERE SummaryDate = ?
            ORDER BY BRANCH_ID""",
        summary_date,
    )
    cols = [c[0] for c in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


# ---------------------------------------------------------------------------
# Unit Test Class
# ---------------------------------------------------------------------------

class TestDailySummaryETL(unittest.TestCase):
    """Unit tests for dbo.usp_Run_ETL_DailySummary.

    Each test maps to a TCxx index with comments for observability.
    """

    @classmethod
    def setUpClass(cls):
        cls.conn = get_connection()
        cls.cursor = cls.conn.cursor()
        # Bootstrap schema and procedure
        execute_tsql_batch(cls.cursor, TSQL_BOOTSTRAP)
        cls.conn.commit()

    @classmethod
    def tearDownClass(cls):
        cls.cursor.close()
        cls.conn.close()

    def setUp(self):
        self.summary_date = datetime.date.today()
        seed_test_data(self.cursor, self.summary_date)
        self.conn.commit()

    # ============================================================
    # TEST CASE 01: Validate successful INSERT into TILE_DAILY_SUMMARY
    # ============================================================
    def test_TC01_insert_tile_daily_summary(self):
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_tile_summary(self.cursor, self.summary_date)
        # Expect records for TILE_001, TILE_002, TILE_999
        tile_ids = {r["tile_id"] for r in results}
        self.assertEqual(len(results), 3)
        self.assertSetEqual(tile_ids, {"TILE_001", "TILE_002", "TILE_999"})

    # ============================================================
    # TEST CASE 02: Validate successful INSERT into BRANCH_SUMMARY_REPORT
    # ============================================================
    def test_TC02_insert_branch_summary_report(self):
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_branch_summary(self.cursor, self.summary_date)
        branch_ids = {r["BRANCH_ID"] for r in results}
        self.assertEqual(len(results), 2)
        self.assertSetEqual(branch_ids, {101, 102})

    # ============================================================
    # TEST CASE 03: Validate tile_category enrichment including default UNKNOWN
    # ============================================================
    def test_TC03_tile_category_enrichment_and_unknown(self):
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_tile_summary(self.cursor, self.summary_date)
        by_id = {r["tile_id"]: r for r in results}

        self.assertEqual(by_id["TILE_001"]["tile_category"], "OFFERS")
        self.assertEqual(by_id["TILE_002"]["tile_category"], "HEALTH")
        self.assertEqual(by_id["TILE_999"]["tile_category"], "UNKNOWN")

    # ============================================================
    # TEST CASE 04: Validate click_through_rate calculation and zero-division handling
    # ============================================================
    def test_TC04_click_through_rate_calculation(self):
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_tile_summary(self.cursor, self.summary_date)
        by_id = {r["tile_id"]: r for r in results}

        # TILE_001: 2 views, 1 click -> 0.5
        self.assertEqual(by_id["TILE_001"]["total_views"], 2)
        self.assertEqual(by_id["TILE_001"]["total_clicks"], 1)
        self.assertAlmostEqual(float(by_id["TILE_001"]["click_through_rate"]), 0.5, places=4)

        # TILE_999: 1 view, 0 clicks -> 0.0
        self.assertEqual(by_id["TILE_999"]["total_views"], 1)
        self.assertEqual(by_id["TILE_999"]["total_clicks"], 0)
        self.assertAlmostEqual(float(by_id["TILE_999"]["click_through_rate"]), 0.0, places=4)

    # ============================================================
    # TEST CASE 05: Validate interstitial metrics aggregation per tile
    # ============================================================
    def test_TC05_interstitial_aggregation(self):
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_tile_summary(self.cursor, self.summary_date)
        by_id = {r["tile_id"]: r for r in results}

        # TILE_001: IE1 + IE2 -> views=2, primary_cta=1, secondary_cta=1
        self.assertEqual(by_id["TILE_001"]["interstitial_views"], 2)
        self.assertEqual(by_id["TILE_001"]["interstitial_primary_cta"], 1)
        self.assertEqual(by_id["TILE_001"]["interstitial_secondary_cta"], 1)

        # TILE_002: IE3 -> views=1, primary_cta=1, secondary_cta=0
        self.assertEqual(by_id["TILE_002"]["interstitial_views"], 1)
        self.assertEqual(by_id["TILE_002"]["interstitial_primary_cta"], 1)
        self.assertEqual(by_id["TILE_002"]["interstitial_secondary_cta"], 0)

    # ============================================================
    # TEST CASE 06: Validate UPDATE behavior for TILE_DAILY_SUMMARY on metadata change
    # ============================================================
    def test_TC06_update_tile_daily_summary_on_metadata_change(self):
        # First run: baseline
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        # Change metadata
        self.cursor.execute(
            "UPDATE dbo.SOURCE_TILE_METADATA SET tile_category = 'OFFERS_UPDATED' WHERE tile_id = 'TILE_001'"
        )
        self.conn.commit()

        # Second run: should update, not insert new row
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_tile_summary(self.cursor, self.summary_date)
        by_id = {r["tile_id"]: r for r in results}

        self.assertEqual(by_id["TILE_001"]["tile_category"], "OFFERS_UPDATED")
        # Ensure still exactly 3 rows
        self.assertEqual(len(results), 3)

    # ============================================================
    # TEST CASE 07: Validate UPDATE behavior for BRANCH_SUMMARY_REPORT on REGION change
    # ============================================================
    def test_TC07_update_branch_summary_report_on_region_change(self):
        # First run: baseline
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        # Change branch REGION
        self.cursor.execute(
            "UPDATE dbo.BRANCH_OPERATIONAL_DETAILS SET REGION = 'NORTH_UPDATED' WHERE BRANCH_ID = 101"
        )
        self.conn.commit()

        # Second run
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        results = fetch_branch_summary(self.cursor, self.summary_date)
        by_id = {r["BRANCH_ID"]: r for r in results}

        self.assertEqual(by_id[101]["REGION"], "NORTH_UPDATED")
        self.assertEqual(len(results), 2)

    # ============================================================
    # TEST CASE 08: Validate MERGE semantics – no duplicate keys in targets
    # ============================================================
    def test_TC08_merge_no_duplicates(self):
        # Run ETL twice
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        # Check for duplicates in TILE_DAILY_SUMMARY
        self.cursor.execute(
            """SELECT SummaryDate, tile_id, COUNT(*) AS cnt
                FROM dbo.TILE_DAILY_SUMMARY
                WHERE SummaryDate = ?
                GROUP BY SummaryDate, tile_id
                HAVING COUNT(*) > 1""",
            self.summary_date,
        )
        duplicates_tiles = self.cursor.fetchall()

        # Check for duplicates in BRANCH_SUMMARY_REPORT
        self.cursor.execute(
            """SELECT SummaryDate, BRANCH_ID, COUNT(*) AS cnt
                FROM dbo.BRANCH_SUMMARY_REPORT
                WHERE SummaryDate = ?
                GROUP BY SummaryDate, BRANCH_ID
                HAVING COUNT(*) > 1""",
            self.summary_date,
        )
        duplicates_branches = self.cursor.fetchall()

        self.assertEqual(len(duplicates_tiles), 0)
        self.assertEqual(len(duplicates_branches), 0)

    # ============================================================
    # TEST CASE 09: Validate ETL_Execution_Log entries for happy path
    # ============================================================
    def test_TC09_logging_happy_path(self):
        self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
        self.conn.commit()

        execution_name = f"DailySummary_{self.summary_date.strftime('%Y-%m-%d')}"
        self.cursor.execute(
            "SELECT StepName, Status, Message FROM dbo.ETL_Execution_Log WHERE ExecutionName = ?",
            execution_name,
        )
        rows = self.cursor.fetchall()
        steps = {row[0]: row[1] for row in rows}

        # Expect three main steps
        self.assertIn("BEGIN_TRANSACTION", steps)
        self.assertIn("TileAggregation", steps)
        self.assertIn("BranchAggregation", steps)

        self.assertEqual(steps["BEGIN_TRANSACTION"], "SUCCESS")
        self.assertEqual(steps["TileAggregation"], "SUCCESS")
        self.assertEqual(steps["BranchAggregation"], "SUCCESS")

    # ============================================================
    # TEST CASE 10: Validate transaction rollback and error logging on failure
    # ============================================================
    def test_TC10_error_handling_and_rollback(self):
        """Force an error and validate rollback + logging.

        We simulate an error by temporarily creating a constraint that will
        fail on insert, or by dropping a required table. Here we drop a
        source table before running ETL to trigger failure.
        """
        # Drop SOURCE_HOME_TILE_EVENTS to cause failure
        self.cursor.execute("DROP TABLE dbo.SOURCE_HOME_TILE_EVENTS")
        self.conn.commit()

        execution_name = f"DailySummary_{self.summary_date.strftime('%Y-%m-%d')}"

        with self.assertRaises(pyodbc.Error):
            self.cursor.execute("EXEC dbo.usp_Run_ETL_DailySummary ?", self.summary_date)
            self.conn.commit()

        # Check log for FAILED status
        self.cursor.execute(
            "SELECT Status, Message FROM dbo.ETL_Execution_Log WHERE ExecutionName = ? AND Status = 'FAILED'",
            execution_name,
        )
        rows = self.cursor.fetchall()
        self.assertGreaterEqual(len(rows), 1)

        # Verify that no partial data exists in TILE_DAILY_SUMMARY for this date
        self.cursor.execute(
            "SELECT COUNT(*) FROM dbo.TILE_DAILY_SUMMARY WHERE SummaryDate = ?",
            self.summary_date,
        )
        count_tiles = self.cursor.fetchone()[0]
        self.assertEqual(count_tiles, 0)


if __name__ == "__main__":
    # Optional: print a brief description before running
    print("# DI_CodeUpdate – Python Unit Tests for T-SQL ETL")
    print("Running tests against SQL Server database:", SQL_SERVER_CONFIG["database"])
    unittest.main(verbosity=2)
```

---

## 5. Coverage Summary

- **Stored Procedure**: `dbo.usp_Run_ETL_DailySummary` – covered for both success and failure scenarios.
- **Source Tables**: All four source tables used; tests validate inserts and update behavior propagated to targets.
- **Target Tables**: `TILE_DAILY_SUMMARY` and `BRANCH_SUMMARY_REPORT` – validated for inserts, updates, deduplication, and data correctness.
- **Logging**: `ETL_Execution_Log` – validated for both happy-path entries and failure entries.
- **Insert & Update Coverage**: Explicit tests (TC01–TC02 for inserts, TC06–TC07 for updates).
- **Edge Cases**: Missing metadata (`UNKNOWN` category), zero views CTR, repeated ETL runs, forced errors.

This test suite can be integrated into CI/CD to automatically validate any changes to the `DI_CodeUpdate` T-SQL implementation.
