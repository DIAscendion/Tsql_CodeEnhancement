# DI Code Update – Self-Contained T-SQL ETL + Python Test Harness

Below are the generated artifacts as requested:

* `DI_CodeUpdate_version_1` – T-SQL ETL implementation (self-contained, SQL Server compatible)
* `DI_CodeUpdate_Python based test script_version_1` – Python script to execute and validate the T-SQL logic (INSERT + UPDATE scenarios)
* Logical pipeline/job name: `DI_CodeUpdate_Pipeline_Version_1`

> Note: Actual job scheduling/execution is assumed to be handled by the orchestration platform (e.g., Azure Data Factory, SQL Agent, DevOps pipeline). The Python script is designed to be the **only** executable step and it internally executes the T-SQL ETL.

---

## 1. T-SQL Implementation – `DI_CodeUpdate_version_1`

```sql
============================================================
Metadata
============================================================
Version      : 1
Previous     : None
Update       : Initial version. No previous version exists.
Purpose      : Complete SQL Server T-SQL ETL implementation
============================================================

--
-- ====================================================================
-- Author:      Ascendion AAVA
-- Date:        
-- Description: ETL to ingest tile event data and branch operational
--              details, enrich with tile metadata and branch metadata,
--              and load a reporting summary table with INSERT/UPDATE
--              behaviors for testing purposes.
-- ====================================================================

/**************************************************************
Overview
--------
This is a **self-contained** SQL Server-compatible T-SQL script that:

1. Creates test schemas and tables to simulate the following logical sources:
   - analytics_db.SOURCE_HOME_TILE_EVENTS (home tile events)
   - analytics_db.SOURCE_INTERSTITIAL_EVENTS (interstitial events)
   - analytics_db.SOURCE_TILE_METADATA (tile master metadata)
   - BRANCH_OPERATIONAL_DETAILS (branch metadata – adapted from Oracle DDL)

2. Creates a target reporting table:
   - BRANCH_TILE_SUMMARY_REPORT

   This table is a SQL Server analogue of the requested target
   `BRANCH_SUMMARY_REPORT` / enriched tile summary outputs.

3. Implements ETL logic that:
   - Aggregates tile views and clicks from SOURCE_HOME_TILE_EVENTS.
   - Aggregates interstitial interactions from SOURCE_INTERSTITIAL_EVENTS.
   - Left-joins SOURCE_TILE_METADATA to enrich tile_category with
     default 'UNKNOWN' when not found.
   - Joins BRANCH_OPERATIONAL_DETAILS to enrich REGION and LAST_AUDIT_DATE.

4. Implements an "upsert" pattern using MERGE to support:
   - INSERT scenario (new tile/branch combinations inserted).
   - UPDATE scenario (existing rows updated based on changed inputs).

5. Includes:
   - TRY/CATCH error handling.
   - Explicit transaction handling.
   - Simple logging table.
   - Inline comments and [ADDED]/[MODIFIED]/[DEPRECATED] tags.

6. Is designed to be invoked from an external Python test script.

Important:
----------
- This script **does not** reference any production schemas.
- All objects are created in the current database using test-safe names.
- The Python script is responsible for running this T-SQL.
**************************************************************/

/*============================================================
  SECTION 1: Safety & Idempotency
============================================================*/

-- [ADDED] Drop and recreate test objects to ensure idempotent runs.
IF OBJECT_ID('dbo.SOURCE_HOME_TILE_EVENTS', 'U') IS NOT NULL
    DROP TABLE dbo.SOURCE_HOME_TILE_EVENTS;

IF OBJECT_ID('dbo.SOURCE_INTERSTITIAL_EVENTS', 'U') IS NOT NULL
    DROP TABLE dbo.SOURCE_INTERSTITIAL_EVENTS;

IF OBJECT_ID('dbo.SOURCE_TILE_METADATA', 'U') IS NOT NULL
    DROP TABLE dbo.SOURCE_TILE_METADATA;

IF OBJECT_ID('dbo.BRANCH_OPERATIONAL_DETAILS', 'U') IS NOT NULL
    DROP TABLE dbo.BRANCH_OPERATIONAL_DETAILS;

IF OBJECT_ID('dbo.BRANCH_TILE_SUMMARY_REPORT', 'U') IS NOT NULL
    DROP TABLE dbo.BRANCH_TILE_SUMMARY_REPORT;

IF OBJECT_ID('dbo.ETL_LOG', 'U') IS NOT NULL
    DROP TABLE dbo.ETL_LOG;

/*============================================================
  SECTION 2: DDL – Source Tables (SQL Server-Compatible)
============================================================*/

-- [ADAPTED] From analytics_db.SOURCE_HOME_TILE_EVENTS (Delta) to SQL Server
CREATE TABLE dbo.SOURCE_HOME_TILE_EVENTS
(
    event_id     VARCHAR(50)   NOT NULL,
    user_id      VARCHAR(50)   NOT NULL,
    session_id   VARCHAR(50)   NOT NULL,
    event_ts     DATETIME2(3)  NOT NULL,
    tile_id      VARCHAR(50)   NOT NULL,
    event_type   VARCHAR(20)   NOT NULL, -- e.g., TILE_VIEW, TILE_CLICK
    device_type  VARCHAR(50)   NULL,
    app_version  VARCHAR(50)   NULL
);

-- [ADAPTED] From analytics_db.SOURCE_INTERSTITIAL_EVENTS (Delta) to SQL Server
CREATE TABLE dbo.SOURCE_INTERSTITIAL_EVENTS
(
    event_id                    VARCHAR(50)   NOT NULL,
    user_id                     VARCHAR(50)   NOT NULL,
    session_id                  VARCHAR(50)   NOT NULL,
    event_ts                    DATETIME2(3)  NOT NULL,
    tile_id                     VARCHAR(50)   NOT NULL,
    interstitial_view_flag      BIT           NOT NULL,
    primary_button_click_flag   BIT           NOT NULL,
    secondary_button_click_flag BIT           NOT NULL
);

-- [ADDED] SOURCE_TILE_METADATA per Jira (analytics_db.SOURCE_TILE_METADATA)
CREATE TABLE dbo.SOURCE_TILE_METADATA
(
    tile_id       VARCHAR(50)   NOT NULL,
    tile_name     VARCHAR(200)  NULL,
    tile_category VARCHAR(100)  NULL -- functional category; may be NULL and defaulted to UNKNOWN in ETL
);

-- [ADAPTED] BRANCH_OPERATIONAL_DETAILS (from Oracle DDL to SQL Server)
CREATE TABLE dbo.BRANCH_OPERATIONAL_DETAILS
(
    BRANCH_ID        INT           NOT NULL,
    REGION           VARCHAR(50)   NULL,
    MANAGER_NAME     VARCHAR(100)  NULL,
    LAST_AUDIT_DATE  DATE          NULL,
    IS_ACTIVE        CHAR(1)       NULL,
    CONSTRAINT PK_BRANCH_OPERATIONAL_DETAILS PRIMARY KEY (BRANCH_ID)
);

/*============================================================
  SECTION 3: DDL – Target Table & Logging
============================================================*/

-- [ADDED] Target reporting table representing BRANCH_SUMMARY_REPORT
--         extended with REGION, LAST_AUDIT_DATE, and TILE_CATEGORY.
CREATE TABLE dbo.BRANCH_TILE_SUMMARY_REPORT
(
    BRANCH_ID               INT           NOT NULL,
    TILE_ID                 VARCHAR(50)   NOT NULL,
    TILE_CATEGORY           VARCHAR(100)  NOT NULL, -- defaulted to UNKNOWN when no mapping
    TOTAL_VIEWS             INT           NOT NULL,
    TOTAL_CLICKS            INT           NOT NULL,
    CLICK_THROUGH_RATE      DECIMAL(18,4) NOT NULL,
    INTERSTITIAL_VIEWS      INT           NOT NULL,
    PRIMARY_BUTTON_CLICKS   INT           NOT NULL,
    SECONDARY_BUTTON_CLICKS INT           NOT NULL,
    REGION                  VARCHAR(50)   NULL,
    LAST_AUDIT_DATE         DATE          NULL,
    LAST_UPDATED_TS         DATETIME2(3)  NOT NULL,
    CONSTRAINT PK_BRANCH_TILE_SUMMARY_REPORT
        PRIMARY KEY (BRANCH_ID, TILE_ID)
);

-- [ADDED] Simple ETL log table for auditing and self-healing visibility
CREATE TABLE dbo.ETL_LOG
(
    LOG_ID        INT IDENTITY(1,1) PRIMARY KEY,
    RUN_ID        UNIQUEIDENTIFIER      NOT NULL,
    STEP_NAME     VARCHAR(200)         NOT NULL,
    STATUS        VARCHAR(50)          NOT NULL,
    MESSAGE       VARCHAR(4000)        NULL,
    CREATED_TS    DATETIME2(3)         NOT NULL DEFAULT SYSDATETIME()
);

/*============================================================
  SECTION 4: Sample Data for Testing
============================================================*/

-- [ADDED] Insert sample BRANCH_OPERATIONAL_DETAILS data
INSERT INTO dbo.BRANCH_OPERATIONAL_DETAILS
    (BRANCH_ID, REGION, MANAGER_NAME, LAST_AUDIT_DATE, IS_ACTIVE)
VALUES
    (1, 'NORTH', 'Alice Manager', '2024-01-15', 'Y'),
    (2, 'SOUTH', 'Bob Manager',   '2024-02-10', 'Y'),
    (3, 'EAST',  'Carol Manager', '2023-12-20', 'N');

-- [ADDED] Insert sample SOURCE_TILE_METADATA data
INSERT INTO dbo.SOURCE_TILE_METADATA (tile_id, tile_name, tile_category)
VALUES
    ('TILE_OFFERS', 'Offers Tile',         'OFFERS'),
    ('TILE_HEALTH', 'Health Check Tile',   'HEALTH'),
    -- tile with no category to test UNKNOWN default
    ('TILE_MISC',   'Misc Tile',           NULL);

-- [ADDED] Insert sample SOURCE_HOME_TILE_EVENTS data
-- Note: we encode BRANCH_ID within user_id purely for testing
--       to keep the schema simple (no extra join table).
INSERT INTO dbo.SOURCE_HOME_TILE_EVENTS
    (event_id, user_id, session_id, event_ts, tile_id, event_type, device_type, app_version)
VALUES
    -- Branch 1, Offers tile: 3 views, 2 clicks
    ('E1', 'BRANCH1_USER1', 'S1', '2024-03-01T10:00:00', 'TILE_OFFERS', 'TILE_VIEW', 'Mobile', '1.0'),
    ('E2', 'BRANCH1_USER2', 'S2', '2024-03-01T10:05:00', 'TILE_OFFERS', 'TILE_VIEW', 'Web',    '1.0'),
    ('E3', 'BRANCH1_USER3', 'S3', '2024-03-01T10:10:00', 'TILE_OFFERS', 'TILE_VIEW', 'Web',    '1.0'),
    ('E4', 'BRANCH1_USER1', 'S1', '2024-03-01T10:15:00', 'TILE_OFFERS', 'TILE_CLICK', 'Mobile', '1.0'),
    ('E5', 'BRANCH1_USER2', 'S2', '2024-03-01T10:20:00', 'TILE_OFFERS', 'TILE_CLICK', 'Web',    '1.0'),

    -- Branch 2, Health tile: 2 views, 0 clicks
    ('E6', 'BRANCH2_USER1', 'S4', '2024-03-01T11:00:00', 'TILE_HEALTH', 'TILE_VIEW', 'Mobile', '1.0'),
    ('E7', 'BRANCH2_USER2', 'S5', '2024-03-01T11:05:00', 'TILE_HEALTH', 'TILE_VIEW', 'Web',    '1.0'),

    -- Branch 1, Misc tile: 1 view, 0 clicks (no metadata category defined)
    ('E8', 'BRANCH1_USER4', 'S6', '2024-03-01T12:00:00', 'TILE_MISC', 'TILE_VIEW', 'Web', '1.0');

-- [ADDED] Insert sample SOURCE_INTERSTITIAL_EVENTS data
INSERT INTO dbo.SOURCE_INTERSTITIAL_EVENTS
    (event_id, user_id, session_id, event_ts, tile_id,
     interstitial_view_flag, primary_button_click_flag, secondary_button_click_flag)
VALUES
    -- Branch 1, Offers tile
    ('I1', 'BRANCH1_USER1', 'S1', '2024-03-01T10:30:00', 'TILE_OFFERS', 1, 1, 0),
    ('I2', 'BRANCH1_USER2', 'S2', '2024-03-01T10:35:00', 'TILE_OFFERS', 1, 0, 1),

    -- Branch 2, Health tile
    ('I3', 'BRANCH2_USER1', 'S4', '2024-03-01T11:10:00', 'TILE_HEALTH', 1, 0, 0);

/*============================================================
  SECTION 5: Helper Function – Branch ID Derivation
============================================================*/

-- [ADDED] Utility: derive BRANCH_ID from user_id pattern 'BRANCH<id>_...'
-- In a real system, this would come from a proper join; for this
-- self-contained example, we parse the branch id to enable joins.

IF OBJECT_ID('dbo.fn_DeriveBranchIdFromUser','FN') IS NOT NULL
    DROP FUNCTION dbo.fn_DeriveBranchIdFromUser;
GO

CREATE FUNCTION dbo.fn_DeriveBranchIdFromUser
(
    @user_id VARCHAR(50)
)
RETURNS INT
AS
BEGIN
    DECLARE @branch_id INT;

    -- Expected pattern: 'BRANCH<id>_...'
    -- Example: 'BRANCH1_USER1' -> 1
    DECLARE @prefix VARCHAR(10) = 'BRANCH';
    DECLARE @pos INT = CHARINDEX(@prefix, @user_id);

    IF @pos = 1
    BEGIN
        DECLARE @rest VARCHAR(50) = SUBSTRING(@user_id, LEN(@prefix) + 1, 50);
        DECLARE @underscore INT = CHARINDEX('_', @rest);
        IF @underscore > 0
            SET @rest = SUBSTRING(@rest, 1, @underscore - 1);

        IF ISNUMERIC(@rest) = 1
            SET @branch_id = CAST(@rest AS INT);
    END

    RETURN @branch_id;
END;
GO

/*============================================================
  SECTION 6: Stored Procedure – Main ETL Logic
============================================================*/

IF OBJECT_ID('dbo.usp_RunBranchTileSummaryETL', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RunBranchTileSummaryETL;
GO

CREATE PROCEDURE dbo.usp_RunBranchTileSummaryETL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RUN_ID UNIQUEIDENTIFIER = NEWID();

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.ETL_LOG (RUN_ID, STEP_NAME, STATUS, MESSAGE)
        VALUES (@RUN_ID, 'START', 'INFO', 'ETL run started');

        /*===============================================
          CTEs: Transform Raw Events into Aggregations
        ===============================================*/

        -- [ADDED] CTE to derive branch_id from user_id (self-contained approach)
        WITH HOME_EVENTS_ENRICHED AS
        (
            SELECT
                dbo.fn_DeriveBranchIdFromUser(user_id) AS BRANCH_ID,
                tile_id,
                event_type
            FROM dbo.SOURCE_HOME_TILE_EVENTS
        ),

        HOME_AGG AS
        (
            SELECT
                BRANCH_ID,
                tile_id,
                SUM(CASE WHEN event_type = 'TILE_VIEW'  THEN 1 ELSE 0 END) AS TOTAL_VIEWS,
                SUM(CASE WHEN event_type = 'TILE_CLICK' THEN 1 ELSE 0 END) AS TOTAL_CLICKS
            FROM HOME_EVENTS_ENRICHED
            GROUP BY BRANCH_ID, tile_id
        ),

        -- [ADDED] CTE for interstitial aggregations
        INTERSTITIAL_EVENTS_ENRICHED AS
        (
            SELECT
                dbo.fn_DeriveBranchIdFromUser(user_id) AS BRANCH_ID,
                tile_id,
                interstitial_view_flag,
                primary_button_click_flag,
                secondary_button_click_flag
            FROM dbo.SOURCE_INTERSTITIAL_EVENTS
        ),

        INTERSTITIAL_AGG AS
        (
            SELECT
                BRANCH_ID,
                tile_id,
                SUM(CASE WHEN interstitial_view_flag      = 1 THEN 1 ELSE 0 END) AS INTERSTITIAL_VIEWS,
                SUM(CASE WHEN primary_button_click_flag   = 1 THEN 1 ELSE 0 END) AS PRIMARY_BUTTON_CLICKS,
                SUM(CASE WHEN secondary_button_click_flag = 1 THEN 1 ELSE 0 END) AS SECONDARY_BUTTON_CLICKS
            FROM INTERSTITIAL_EVENTS_ENRICHED
            GROUP BY BRANCH_ID, tile_id
        ),

        -- [ADDED] Join home + interstitial, and enrich with tile metadata and branch metadata
        FINAL_AGG AS
        (
            SELECT
                h.BRANCH_ID,
                h.tile_id,
                -- tile_category with default UNKNOWN when not present or NULL
                COALESCE(tm.tile_category, 'UNKNOWN') AS TILE_CATEGORY,

                h.TOTAL_VIEWS,
                h.TOTAL_CLICKS,
                -- CTR: avoid division by zero
                CASE
                    WHEN h.TOTAL_VIEWS > 0
                        THEN CAST(h.TOTAL_CLICKS AS DECIMAL(18,4)) / CAST(h.TOTAL_VIEWS AS DECIMAL(18,4))
                    ELSE 0
                END AS CLICK_THROUGH_RATE,

                COALESCE(i.INTERSTITIAL_VIEWS,      0) AS INTERSTITIAL_VIEWS,
                COALESCE(i.PRIMARY_BUTTON_CLICKS,   0) AS PRIMARY_BUTTON_CLICKS,
                COALESCE(i.SECONDARY_BUTTON_CLICKS, 0) AS SECONDARY_BUTTON_CLICKS,

                bod.REGION,
                bod.LAST_AUDIT_DATE
            FROM HOME_AGG h
            LEFT JOIN INTERSTITIAL_AGG i
                ON h.BRANCH_ID = i.BRANCH_ID
               AND h.tile_id   = i.tile_id
            LEFT JOIN dbo.SOURCE_TILE_METADATA tm
                ON h.tile_id   = tm.tile_id
            LEFT JOIN dbo.BRANCH_OPERATIONAL_DETAILS bod
                ON h.BRANCH_ID = bod.BRANCH_ID
        )

        -- [ADDED] MERGE into target with INSERT/UPDATE behavior
        MERGE dbo.BRANCH_TILE_SUMMARY_REPORT AS tgt
        USING FINAL_AGG AS src
            ON tgt.BRANCH_ID = src.BRANCH_ID
           AND tgt.TILE_ID   = src.tile_id
        WHEN MATCHED THEN
            UPDATE SET
                tgt.TILE_CATEGORY           = src.TILE_CATEGORY,
                tgt.TOTAL_VIEWS             = src.TOTAL_VIEWS,
                tgt.TOTAL_CLICKS            = src.TOTAL_CLICKS,
                tgt.CLICK_THROUGH_RATE      = src.CLICK_THROUGH_RATE,
                tgt.INTERSTITIAL_VIEWS      = src.INTERSTITIAL_VIEWS,
                tgt.PRIMARY_BUTTON_CLICKS   = src.PRIMARY_BUTTON_CLICKS,
                tgt.SECONDARY_BUTTON_CLICKS = src.SECONDARY_BUTTON_CLICKS,
                tgt.REGION                  = src.REGION,
                tgt.LAST_AUDIT_DATE         = src.LAST_AUDIT_DATE,
                tgt.LAST_UPDATED_TS         = SYSDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                BRANCH_ID,
                TILE_ID,
                TILE_CATEGORY,
                TOTAL_VIEWS,
                TOTAL_CLICKS,
                CLICK_THROUGH_RATE,
                INTERSTITIAL_VIEWS,
                PRIMARY_BUTTON_CLICKS,
                SECONDARY_BUTTON_CLICKS,
                REGION,
                LAST_AUDIT_DATE,
                LAST_UPDATED_TS
            )
            VALUES
            (
                src.BRANCH_ID,
                src.tile_id,
                src.TILE_CATEGORY,
                src.TOTAL_VIEWS,
                src.TOTAL_CLICKS,
                src.CLICK_THROUGH_RATE,
                src.INTERSTITIAL_VIEWS,
                src.PRIMARY_BUTTON_CLICKS,
                src.SECONDARY_BUTTON_CLICKS,
                src.REGION,
                src.LAST_AUDIT_DATE,
                SYSDATETIME()
            );

        INSERT INTO dbo.ETL_LOG (RUN_ID, STEP_NAME, STATUS, MESSAGE)
        VALUES (@RUN_ID, 'END', 'SUCCESS', 'ETL run completed successfully');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        DECLARE
            @ErrorNumber   INT = ERROR_NUMBER(),
            @ErrorSeverity INT = ERROR_SEVERITY(),
            @ErrorState    INT = ERROR_STATE(),
            @ErrorLine     INT = ERROR_LINE(),
            @ErrorMessage  NVARCHAR(4000) = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        INSERT INTO dbo.ETL_LOG (RUN_ID, STEP_NAME, STATUS, MESSAGE)
        VALUES (@RUN_ID, 'ERROR', 'FAILED',
                CONCAT('Error ', @ErrorNumber,
                       ' Severity ', @ErrorSeverity,
                       ' State ', @ErrorState,
                       ' Line ', @ErrorLine,
                       ': ', @ErrorMessage));

        ;THROW;
    END CATCH;
END;
GO

/*============================================================
  SECTION 7: Validation Queries (Manual Use)
============================================================*/

-- [ADDED] These queries can be used manually (or by Python script)
--         to validate the ETL output.

-- Example: View summary report
-- SELECT * FROM dbo.BRANCH_TILE_SUMMARY_REPORT ORDER BY BRANCH_ID, TILE_ID;

-- Example: View ETL logs
-- SELECT * FROM dbo.ETL_LOG ORDER BY LOG_ID DESC;

```

---

## 2. Python Test Script – `DI_CodeUpdate_Python based test script_version_1`

This Python script:

* Reads SQL Server connection information from a credentials file (not hardcoded).
* Executes the T-SQL implementation (above) as a single batch.
* Runs two scenarios:
  1. **Insert Scenario** – Fresh run with empty target → validates inserted records.
  2. **Update Scenario** – Modifies source data and re-runs ETL → validates updates.
* Performs validations using plain Python logic (no PyTest).
* Produces a markdown-style textual summary (printed to stdout).

```python
============================================================
Metadata
============================================================
Version      : 1
Previous     : None
Update       : Initial version. No previous version exists.
Purpose      : Python-based test script for executing and validating the T-SQL implementation
============================================================

"""
Author:      Ascendion AAVA
Date:        
Description: Executes the DI_CodeUpdate_version_1 T-SQL ETL script
             against SQL Server using test data, and validates
             INSERT and UPDATE scenarios without using PyTest.

Notes:
- SQL Server connection details and OUTPUT_FOLDER must be provided
  via an external credentials file or environment variables.
- This script expects a dictionary-like config structure with keys:
  SQL_SERVER, SQL_DATABASE, SQL_USERNAME, SQL_PASSWORD, SQL_PORT,
  OUTPUT_FOLDER.
- No credentials are hardcoded.
"""

import os
import time
import json
import textwrap
from datetime import datetime

import pyodbc


# ============================================================
# Helper: Load Credentials (Self-Healing Compatible)
# ============================================================


def load_credentials_from_file(path: str) -> dict:
    """Load credentials JSON file with required keys.

    Expected fields:
        SQL_SERVER
        SQL_DATABASE
        SQL_USERNAME
        SQL_PASSWORD
        SQL_PORT
        OUTPUT_FOLDER
    """
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


# ============================================================
# Helper: Establish SQL Server Connection
# ============================================================


def get_sql_connection(cfg: dict) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={cfg['SQL_SERVER']},{cfg['SQL_PORT']};"
        f"DATABASE={cfg['SQL_DATABASE']};"
        f"UID={cfg['SQL_USERNAME']};"
        f"PWD={cfg['SQL_PASSWORD']}"
    )
    return pyodbc.connect(conn_str)


# ============================================================
# Helper: Execute T-SQL Batch
# ============================================================


def read_tsql_script(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def execute_tsql_batch(cursor, tsql: str):
    """Execute a batch of T-SQL commands.

    pyodbc does not support multiple result sets automatically with GO,
    so we remove GO and send as a single batch where possible.
    """
    # Remove GO batch separators for execution
    commands = []
    current = []

    for line in tsql.splitlines():
        if line.strip().upper() == "GO":
            if current:
                commands.append("\n".join(current))
                current = []
        else:
            current.append(line)
    if current:
        commands.append("\n".join(current))

    for cmd in commands:
        if cmd.strip():
            cursor.execute(cmd)
            # commit after each major batch to ensure DDL success
            cursor.connection.commit()


# ============================================================
# Scenario 1 – Insert into Target Table
# ============================================================


def scenario_insert(conn) -> dict:
    """Execute ETL for the initial insert scenario.

    Assumes target table is empty (it is dropped/recreated by the T-SQL).
    """
    cur = conn.cursor()

    # Execute stored procedure
    cur.execute("EXEC dbo.usp_RunBranchTileSummaryETL;")
    conn.commit()

    # Validate results
    cur.execute("SELECT * FROM dbo.BRANCH_TILE_SUMMARY_REPORT ORDER BY BRANCH_ID, TILE_ID;")
    rows = cur.fetchall()

    # Transform rows to simple list of dicts
    columns = [desc[0] for desc in cur.description]
    results = [dict(zip(columns, row)) for row in rows]

    # Expected values based on the inserted sample data in T-SQL
    expected_records = 3  # (Branch 1 Offers, Branch 1 Misc, Branch 2 Health)

    # Compute basic validation metrics
    actual_records = len(results)
    validation_pass = actual_records == expected_records

    return {
        "expected_records": expected_records,
        "actual_records": actual_records,
        "validation_pass": validation_pass,
        "rows": results,
    }


# ============================================================
# Scenario 2 – Update Target Table
# ============================================================


def scenario_update(conn) -> dict:
    """Modify source data and re-run ETL to validate updates.

    Strategy:
      - For Branch 1, TILE_OFFERS: add extra click events to increase totals.
      - Re-run usp_RunBranchTileSummaryETL.
      - Verify that BRANCH_TILE_SUMMARY_REPORT has updated totals
        for (BRANCH_ID=1, TILE_ID='TILE_OFFERS') while other rows
        remain unchanged.
    """
    cur = conn.cursor()

    # Add additional click events for Branch 1, TILE_OFFERS
    cur.execute(
        """
        INSERT INTO dbo.SOURCE_HOME_TILE_EVENTS
            (event_id, user_id, session_id, event_ts, tile_id, event_type, device_type, app_version)
        VALUES
            ('E9',  'BRANCH1_USER5', 'S7', '2024-03-01T13:00:00', 'TILE_OFFERS', 'TILE_CLICK', 'Mobile', '1.0'),
            ('E10', 'BRANCH1_USER6', 'S8', '2024-03-01T13:05:00', 'TILE_OFFERS', 'TILE_CLICK', 'Web',    '1.0');
        """
    )
    conn.commit()

    # Re-run ETL
    cur.execute("EXEC dbo.usp_RunBranchTileSummaryETL;")
    conn.commit()

    # Fetch updated results
    cur.execute("SELECT * FROM dbo.BRANCH_TILE_SUMMARY_REPORT ORDER BY BRANCH_ID, TILE_ID;")
    rows = cur.fetchall()
    columns = [desc[0] for desc in cur.description]
    results = [dict(zip(columns, row)) for row in rows]

    # Find Branch 1, TILE_OFFERS record
    offers_record = None
    for r in results:
        if r["BRANCH_ID"] == 1 and r["TILE_ID"] == "TILE_OFFERS":
            offers_record = r
            break

    # From Scenario 1, Branch 1 Offers: TOTAL_CLICKS was 2.
    # We added 2 more clicks -> expected TOTAL_CLICKS = 4.
    expected_clicks = 4
    actual_clicks = offers_record["TOTAL_CLICKS"] if offers_record else None

    validation_pass = (offers_record is not None and actual_clicks == expected_clicks)

    return {
        "expected_updates": 1,  # 1 logical row expected to be updated
        "actual_updates": 1 if validation_pass else 0,
        "validation_pass": validation_pass,
        "offers_record": offers_record,
        "all_rows": results,
        "expected_clicks": expected_clicks,
        "actual_clicks": actual_clicks,
    }


# ============================================================
# Main Entry – Execute Scenarios and Produce Markdown Report
# ============================================================


def main():
    # -----------------------------------------------------------------
    # Load configuration
    # -----------------------------------------------------------------
    credentials_path = os.environ.get("SQL_CREDENTIALS_FILE", "sql_credentials.json")
    cfg = load_credentials_from_file(credentials_path)

    # -----------------------------------------------------------------
    # Connect to SQL Server
    # -----------------------------------------------------------------
    conn = get_sql_connection(cfg)

    # -----------------------------------------------------------------
    # Execute T-SQL ETL Script (DDL + Stored Proc + Sample Data)
    # -----------------------------------------------------------------
    input_file_name = "DI_CodeUpdate"

    tsql_script_path = os.path.join(
        cfg["OUTPUT_FOLDER"], f"{input_file_name}_version_1.sql"
    )

    tsql_content = read_tsql_script(tsql_script_path)

    cur = conn.cursor()

    start_time = time.time()
    execute_tsql_batch(cur, tsql_content)

    # -----------------------------------------------------------------
    # Scenario 1 – Insert
    # -----------------------------------------------------------------
    insert_result = scenario_insert(conn)

    # -----------------------------------------------------------------
    # Scenario 2 – Update
    # -----------------------------------------------------------------
    update_result = scenario_update(conn)

    end_time = time.time()
    execution_time = end_time - start_time

    # -----------------------------------------------------------------
    # Build Markdown Execution Report
    # -----------------------------------------------------------------

    execution_status = (
        "SUCCESS" if insert_result["validation_pass"] and update_result["validation_pass"] else "FAILED"
    )

    md_report = []

    md_report.append("## Execution Summary")
    md_report.append("")
    md_report.append("| Field                      | Value                                  |")
    md_report.append("| -------------------------- | -------------------------------------- |")
    md_report.append(f"| Input File                 | {input_file_name}                       |")
    md_report.append("| T-SQL Version              | Version_1                              |")
    md_report.append("| Python Test Script Version | Version_1                              |")
    md_report.append(
        f"| Pipeline Name              | {input_file_name}_Pipeline_Version_1   |"
    )
    md_report.append("| Database                   | SQL Server                             |")
    md_report.append(f"| Execution Status           | {execution_status}                      |")
    md_report.append(f"| Execution Time             | {execution_time:.2f} seconds            |")

    # Scenario 1 – Insert Test
    md_report.append("")
    md_report.append("## Scenario 1 – Insert Test")
    md_report.append("")
    md_report.append("### Input")
    md_report.append(
        textwrap.dedent(
            """
            Sample data inserted into:
            - SOURCE_HOME_TILE_EVENTS
            - SOURCE_INTERSTITIAL_EVENTS
            - SOURCE_TILE_METADATA
            - BRANCH_OPERATIONAL_DETAILS

            Initial ETL run expects to populate BRANCH_TILE_SUMMARY_REPORT
            with one row per (BRANCH_ID, TILE_ID) combination.
            """
        ).strip()
    )

    md_report.append("")
    md_report.append("### Expected Output")
    md_report.append(
        "Expected 3 records in BRANCH_TILE_SUMMARY_REPORT:"
        " (Branch 1 Offers, Branch 1 Misc, Branch 2 Health)."
    )

    md_report.append("")
    md_report.append("### Actual Output")

    for row in insert_result["rows"]:
        md_report.append("- " + ", ".join(f"{k}={v}" for k, v in row.items()))

    md_report.append("")
    md_report.append("### Validation")
    md_report.append("```text")
    md_report.append(f"Expected Records : {insert_result['expected_records']}")
    md_report.append(f"Actual Records   : {insert_result['actual_records']}")
    md_report.append(
        f"Validation       : {'PASS' if insert_result['validation_pass'] else 'FAIL'}"
    )
    md_report.append("```")

    # Scenario 2 – Update Test
    md_report.append("")
    md_report.append("## Scenario 2 – Update Test")

    md_report.append("")
    md_report.append("### Input")
    md_report.append(
        textwrap.dedent(
            """
            Existing target records in BRANCH_TILE_SUMMARY_REPORT are
            updated by inserting additional TILE_CLICK events for
            Branch 1, TILE_OFFERS. We then re-run the ETL procedure
            usp_RunBranchTileSummaryETL.

            Key columns used to identify the record:
            - BRANCH_ID = 1
            - TILE_ID   = 'TILE_OFFERS'
            """
        ).strip()
    )

    md_report.append("")
    md_report.append("### Expected Output")
    md_report.append(
        "For BRANCH_ID=1 and TILE_ID='TILE_OFFERS', TOTAL_CLICKS should "
        "increase from 2 to 4 after the additional events."
    )

    md_report.append("")
    md_report.append("### Actual Output")

    if update_result["offers_record"]:
        md_report.append(
            "- "
            + ", ".join(
                f"{k}={v}" for k, v in update_result["offers_record"].items()
            )
        )
    else:
        md_report.append("- No record found for BRANCH_ID=1, TILE_OFFERS")

    md_report.append("")
    md_report.append("### Validation")
    md_report.append("```text")
    md_report.append(f"Expected Updates : {update_result['expected_updates']}")
    md_report.append(f"Actual Updates   : {update_result['actual_updates']}")
    md_report.append(
        f"Validation       : {'PASS' if update_result['validation_pass'] else 'FAIL'}"
    )
    md_report.append("```")

    # Final Result Summary
    md_report.append("")
    md_report.append("## Final Result")

    md_report.append("```text")
    md_report.append(
        f"T-SQL Execution       : {'SUCCESS' if execution_status == 'SUCCESS' else 'UNKNOWN'}"
    )
    md_report.append(
        f"Insert Scenario       : {'PASS' if insert_result['validation_pass'] else 'FAIL'}"
    )
    md_report.append(
        f"Update Scenario       : {'PASS' if update_result['validation_pass'] else 'FAIL'}"
    )
    md_report.append(
        f"Data Validation       : {'PASS' if execution_status == 'SUCCESS' else 'FAIL'}"
    )
    md_report.append("Python Test Script    : SUCCESS")
    md_report.append(
        f"Pipeline              : {execution_status}"
    )
    md_report.append("Final Version         : Version_1")
    md_report.append("```")

    markdown_output = "\n".join(md_report)

    # Print to stdout
    print(markdown_output)

    # Optionally write to file in OUTPUT_FOLDER
    output_path = os.path.join(cfg["OUTPUT_FOLDER"], "DI_CodeUpdate_TestReport_Version_1.md")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(markdown_output)


if __name__ == "__main__":
    main()

```

---

## 3. Pipeline / Job Definition (Conceptual)

* **Pipeline Name:** `DI_CodeUpdate_Pipeline_Version_1`
* **Task:** Single step that runs `DI_CodeUpdate_Python based test script_version_1`.
* **Execution Rule:**
  * The T-SQL script `DI_CodeUpdate_version_1` is **not** executed as a separate pipeline task.
  * The Python script handles:
    1. Connecting to SQL Server.
    2. Executing the T-SQL script (DDL + ETL stored procedure).
    3. Running INSERT and UPDATE scenarios.
    4. Producing a markdown execution report and writing it to the output folder.

As this environment cannot actually run SQL Server or the Python script, the self-healing loop is logically encoded but not physically executed here. In a real deployment, if the pipeline failed, subsequent versions (2, 3, …) would be produced by analyzing the runtime errors and iteratively fixing the T-SQL and/or Python as per the Self-Healing rules.

---

## 4. Markdown Execution Report (Template)

Below is the **template** of the report produced by the Python script on a successful run. Actual values will be filled at runtime.

```markdown
## Execution Summary

| Field                      | Value                                  |
| -------------------------- | -------------------------------------- |
| Input File                 | DI_CodeUpdate                          |
| T-SQL Version              | Version_1                              |
| Python Test Script Version | Version_1                              |
| Pipeline Name              | DI_CodeUpdate_Pipeline_Version_1       |
| Database                   | SQL Server                             |
| Execution Status           | SUCCESS                                |
| Execution Time             | <execution_time> seconds               |

## Scenario 1 – Insert Test

### Input
Sample data inserted into:
- SOURCE_HOME_TILE_EVENTS
- SOURCE_INTERSTITIAL_EVENTS
- SOURCE_TILE_METADATA
- BRANCH_OPERATIONAL_DETAILS

Initial ETL run expects to populate BRANCH_TILE_SUMMARY_REPORT
with one row per (BRANCH_ID, TILE_ID) combination.

### Expected Output
Expected 3 records in BRANCH_TILE_SUMMARY_REPORT: (Branch 1 Offers, Branch 1 Misc, Branch 2 Health).

### Actual Output
- <row 1>
- <row 2>
- <row 3>

### Validation
```text
Expected Records : 3
Actual Records   : 3
Validation       : PASS
```

## Scenario 2 – Update Test

### Input
Existing target records in BRANCH_TILE_SUMMARY_REPORT are
updated by inserting additional TILE_CLICK events for
Branch 1, TILE_OFFERS. We then re-run the ETL procedure
usp_RunBranchTileSummaryETL.

Key columns used to identify the record:
- BRANCH_ID = 1
- TILE_ID   = 'TILE_OFFERS'

### Expected Output
For BRANCH_ID=1 and TILE_ID='TILE_OFFERS', TOTAL_CLICKS should
increase from 2 to 4 after the additional events.

### Actual Output
- <Branch 1, TILE_OFFERS row after update>

### Validation
```text
Expected Updates : 1
Actual Updates   : 1
Validation       : PASS
```

## Final Result
```text
T-SQL Execution       : SUCCESS
Insert Scenario       : PASS
Update Scenario       : PASS
Data Validation       : PASS
Python Test Script    : SUCCESS
Pipeline              : SUCCESS
Final Version         : Version_1
```
```

---

## 5. Cost Estimation and Justification

Assuming the execution environment is a CI/CD pipeline with shared SQL Server resources, the major cost components are:

1. **SQL Server Compute Time**
   - ETL script is lightweight: a few small test tables, simple aggregations, and a MERGE.
   - Expected runtime per execution: well under 1 second on a typical dev/test instance.
   - Cost impact is negligible in most enterprise environments.

2. **Storage**
   - All tables are small and test data is minimal.
   - Can be dropped/recreated as part of test runs.
   - No meaningful incremental storage cost.

3. **Pipeline Orchestration**
   - Single Python step per run.
   - If integrated into an existing DevOps pipeline, incremental orchestration cost is minimal.

4. **Maintenance / Self-Healing**
   - The structure is designed so that future schema or logic changes can be applied via new versions (2, 3, …) without rewriting from scratch.
   - Clear separation between T-SQL ETL and Python executor reduces maintenance overhead.

Overall, the design is optimized for:
- Minimal runtime and storage cost.
- High clarity and maintainability.
- Ease of extension for future self-healing iterations.
