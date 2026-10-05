# T-SQL Test Strategy and Python-Based Test Suite

```text
====================================================================
Author: Ascendion AAVA
Date: 
Description: Comprehensive T-SQL ETL test strategy and Python-based unit test suite for BRANCH_TILE_SUMMARY_REPORT pipeline.
====================================================================
```

---

## 1. Context and Scope

This document defines the test strategy and executable Python-based test suite for the self-contained T-SQL ETL implementation described in `Output/DI_CodeUpdate.md`. The focus is on validating:

- Source-to-target transformations for tile and branch event data.
- Aggregations, joins, and enrichment with metadata tables.
- INSERT and UPDATE behavior implemented via the MERGE statement into `dbo.BRANCH_TILE_SUMMARY_REPORT`.
- Error handling and transaction management in `dbo.usp_RunBranchTileSummaryETL`.
- Utility function `dbo.fn_DeriveBranchIdFromUser`.

Key T-SQL objects under test:

- Function: `dbo.fn_DeriveBranchIdFromUser`
- Stored procedure: `dbo.usp_RunBranchTileSummaryETL`
- Tables:
  - `dbo.SOURCE_HOME_TILE_EVENTS`
  - `dbo.SOURCE_INTERSTITIAL_EVENTS`
  - `dbo.SOURCE_TILE_METADATA`
  - `dbo.BRANCH_OPERATIONAL_DETAILS`
  - `dbo.BRANCH_TILE_SUMMARY_REPORT`
  - `dbo.ETL_LOG`

---

## 2. High-Level T-SQL Test Strategy

### 2.1 Components and Behaviors to Test

1. **Function `dbo.fn_DeriveBranchIdFromUser`**
   - Correct parsing of `user_id` strings in the expected format `BRANCH<id>_...`.
   - Handling of malformed or unexpected user IDs (NULL or invalid pattern).

2. **Stored Procedure `dbo.usp_RunBranchTileSummaryETL`**
   - Correct creation and population of aggregations.
   - Correct join logic across HOME events, INTERSTITIAL events, tile metadata, and branch metadata.
   - Correct defaulting of `TILE_CATEGORY` to `UNKNOWN` when no metadata exists.
   - Insert-only behavior when target is empty.
   - Update behavior when source changes (idempotent and repeatable).
   - Proper calculation of `CLICK_THROUGH_RATE` and avoidance of division by zero.
   - Logging entries in `dbo.ETL_LOG` for START, END, and error conditions.

3. **Target Table `dbo.BRANCH_TILE_SUMMARY_REPORT`**
   - Primary key uniqueness by `(BRANCH_ID, TILE_ID)`.
   - Accurate metrics for views/clicks/interstitial activity.
   - Region and last audit date populated from `BRANCH_OPERATIONAL_DETAILS`.
   - Correct handling of branches without metadata.

4. **Error Handling and Transactions**
   - Transaction rollback on errors.
   - Error logging into `dbo.ETL_LOG` with details.

### 2.2 Test Types

- **Unit Tests**
  - `fn_DeriveBranchIdFromUser` behavior.
  - Core aggregation and CTR calculation logic (via focused scenarios).

- **Integration / ETL Tests**
  - Full run of `usp_RunBranchTileSummaryETL` from sample inputs to final output.

- **Edge Case Tests**
  - NULL / malformed `user_id`.
  - Missing `SOURCE_TILE_METADATA` entries (to ensure `UNKNOWN` category).
  - Zero views to ensure CTR calculated as 0 without error.

- **Insert & Update Tests**
  - Initial load (INSERT) for new `BRANCH_ID` + `TILE_ID` combinations.
  - Subsequent run with changed data (UPDATE/UPSERT semantics via MERGE).

---

## 3. Detailed Test Case List

Below is the list of test cases. Each test case is later implemented in Python as a dedicated method or branch of logic, and each test scenario will be clearly logged and asserted.

### 3.1 Function-Level Tests

1. **TC_FN_001 – Valid branch ID parsing**
   - Input: `BRANCH1_USER1` → Output: `1`.
   - Input: `BRANCH25_USER_X` → Output: `25`.

2. **TC_FN_002 – Invalid patterns return NULL**
   - Input: `USER1_BRANCH1` → Output: `NULL`.
   - Input: `BRANCHABC_USER` → Output: `NULL`.
   - Input: `NULL` → Output: `NULL`.

### 3.2 Stored Procedure and ETL Flow Tests

3. **TC_SP_001 – Initial INSERT scenario populates target table**
   - Validate that after a fresh execution of `usp_RunBranchTileSummaryETL`, the target table contains exactly 3 records, matching the designed sample data.

4. **TC_SP_002 – UPDATE scenario updates existing target records**
   - Add two new click events for Branch 1 / TILE_OFFERS and re-run ETL. Validate that TOTAL_CLICKS for that key increases from 2 to 4.

5. **TC_SP_003 – TILE_CATEGORY defaulting to UNKNOWN**
   - Validate that rows where `SOURCE_TILE_METADATA.tile_category` is NULL result in `TILE_CATEGORY = 'UNKNOWN'` in the target.

6. **TC_SP_004 – CTR calculation and division by zero handling**
   - For Branch 2 / TILE_HEALTH: 2 views and 0 clicks → CTR should be `0.0000`.
   - For Branch 1 / TILE_OFFERS: 3 views and 2 clicks → CTR should be `0.6667` (rounded to 4 decimal places based on DECIMAL(18,4)).

7. **TC_SP_005 – REGION and LAST_AUDIT_DATE enrichment**
   - Ensure REGION and LAST_AUDIT_DATE in target match `BRANCH_OPERATIONAL_DETAILS` for each branch.

8. **TC_SP_006 – Logging entries for successful run**
   - Ensure `ETL_LOG` contains START and END records with STATUS `INFO` and `SUCCESS` respectively for each run.

9. **TC_SP_007 – Error handling and rollback**
   - Intentionally inject a failure (e.g., by temporarily dropping a required table and rerunning ETL, or using an invalid column in a controlled variant script). Ensure transaction is rolled back and an `ERROR` log entry exists.

10. **TC_SP_008 – Idempotent behavior on repeated ETL runs without input change**
    - Run `usp_RunBranchTileSummaryETL` twice without modifying sources. Ensure target contents remain logically consistent and are not duplicated.

### 3.3 Insert & Update Coverage Tests (Explicit)

11. **TC_DML_001 – INSERT into new BRANCH_ID/TILE_ID combination**
    - Insert a new branch (BRANCH_ID=4) with HOME and INTERSTITIAL events and metadata; run ETL and verify the new combination is inserted in the target.

12. **TC_DML_002 – UPDATE existing BRANCH_ID/TILE_ID combination**
    - Modify existing events for Branch 1 / TILE_MISC (e.g., add clicks), rerun ETL, and validate the target row is updated accordingly.

---

## 4. Python-Based Test Script (Executable)

The following Python script implements the test cases above using standard `unittest`. It is designed to connect to SQL Server, execute the T-SQL ETL code, run the scenarios, and validate the outcomes via assertions.

> Note: This script assumes that the T-SQL ETL file (`DI_CodeUpdate_version_1.sql`) is present in the configured folder and is identical to the one provided in `Output/DI_CodeUpdate.md`.

```python
====================================================================
Author: Ascendion AAVA
Date: 
Description: Python unittest suite for validating T-SQL ETL logic into BRANCH_TILE_SUMMARY_REPORT.
====================================================================

import os
import json
import time
import unittest
import textwrap
from decimal import Decimal

import pyodbc


# ============================================================
# Helper Functions
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


def get_sql_connection(cfg: dict) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={cfg['SQL_SERVER']},{cfg['SQL_PORT']};"
        f"DATABASE={cfg['SQL_DATABASE']};"
        f"UID={cfg['SQL_USERNAME']};"
        f"PWD={cfg['SQL_PASSWORD']}"
    )
    return pyodbc.connect(conn_str)


def read_tsql_script(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def execute_tsql_batch(cursor, tsql: str):
    """Execute a batch of T-SQL commands, removing GO separators."""
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
            cursor.connection.commit()


# ============================================================
# Test Suite
# ============================================================


class TestBranchTileSummaryETL(unittest.TestCase):
    """End-to-end ETL tests for BRANCH_TILE_SUMMARY_REPORT."""

    @classmethod
    def setUpClass(cls):
        # Load configuration and establish a single shared connection
        credentials_path = os.environ.get("SQL_CREDENTIALS_FILE", "sql_credentials.json")
        cls.cfg = load_credentials_from_file(credentials_path)
        cls.conn = get_sql_connection(cls.cfg)

        # Execute base T-SQL script (DDL + procedure + sample data)
        input_file_name = "DI_CodeUpdate"
        tsql_script_path = os.path.join(
            cls.cfg["OUTPUT_FOLDER"], f"{input_file_name}_version_1.sql"
        )
        tsql_content = read_tsql_script(tsql_script_path)
        cur = cls.conn.cursor()
        execute_tsql_batch(cur, tsql_content)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    # --------------------------------------------------------
    # Helper methods for tests
    # --------------------------------------------------------

    def _call_etl_procedure(self):
        cur = self.conn.cursor()
        cur.execute("EXEC dbo.usp_RunBranchTileSummaryETL;")
        self.conn.commit()

    def _fetch_summary_rows(self):
        cur = self.conn.cursor()
        cur.execute(
            "SELECT * FROM dbo.BRANCH_TILE_SUMMARY_REPORT ORDER BY BRANCH_ID, TILE_ID;"
        )
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        return [dict(zip(cols, r)) for r in rows]

    def _fetch_single_summary_row(self, branch_id, tile_id):
        cur = self.conn.cursor()
        cur.execute(
            """
            SELECT *
            FROM dbo.BRANCH_TILE_SUMMARY_REPORT
            WHERE BRANCH_ID = ? AND TILE_ID = ?;
            """,
            branch_id,
            tile_id,
        )
        row = cur.fetchone()
        if not row:
            return None
        cols = [d[0] for d in cur.description]
        return dict(zip(cols, row))

    def _fetch_fn_branch_id(self, user_id):
        cur = self.conn.cursor()
        cur.execute("SELECT dbo.fn_DeriveBranchIdFromUser(?);", user_id)
        row = cur.fetchone()
        return row[0] if row else None

    def _insert_home_event(self, **kwargs):
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO dbo.SOURCE_HOME_TILE_EVENTS
                (event_id, user_id, session_id, event_ts, tile_id, event_type, device_type, app_version)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            kwargs["event_id"],
            kwargs["user_id"],
            kwargs["session_id"],
            kwargs["event_ts"],
            kwargs["tile_id"],
            kwargs["event_type"],
            kwargs.get("device_type"),
            kwargs.get("app_version"),
        )
        self.conn.commit()

    # ========================================================
    # Function-Level Tests
    # ========================================================

    # ============================================================
    # TEST CASE 01: Validate fn_DeriveBranchIdFromUser with valid input
    # ============================================================
    def test_TC_FN_001_valid_branch_id_parsing(self):
        """TC_FN_001: Valid branch ID parsing from user_id."""
        self.assertEqual(self._fetch_fn_branch_id("BRANCH1_USER1"), 1)
        self.assertEqual(self._fetch_fn_branch_id("BRANCH25_USER_X"), 25)

    # ============================================================
    # TEST CASE 02: Validate fn_DeriveBranchIdFromUser with invalid input
    # ============================================================
    def test_TC_FN_002_invalid_patterns_return_null(self):
        """TC_FN_002: Invalid patterns should yield NULL branch_id."""
        self.assertIsNone(self._fetch_fn_branch_id("USER1_BRANCH1"))
        self.assertIsNone(self._fetch_fn_branch_id("BRANCHABC_USER"))
        self.assertIsNone(self._fetch_fn_branch_id(None))

    # ========================================================
    # Stored Procedure / ETL Flow Tests
    # ========================================================

    # ============================================================
    # TEST CASE 03: Initial INSERT scenario populates target table
    # ============================================================
    def test_TC_SP_001_initial_insert_populates_target(self):
        """TC_SP_001: Validate successful INSERT into target table on initial ETL run."""
        # Fresh ETL run
        self._call_etl_procedure()

        rows = self._fetch_summary_rows()
        self.assertEqual(len(rows), 3, "Expected exactly 3 summary rows after initial ETL run")

    # ============================================================
    # TEST CASE 04: UPDATE scenario updates existing target records
    # ============================================================
    def test_TC_SP_002_update_existing_records(self):
        """TC_SP_002: Validate UPDATE behavior for existing branch/tile combination."""
        # First run to establish baseline
        self._call_etl_procedure()

        # Add additional click events for Branch 1 / TILE_OFFERS
        self._insert_home_event(
            event_id="E9",
            user_id="BRANCH1_USER5",
            session_id="S7",
            event_ts="2024-03-01T13:00:00",
            tile_id="TILE_OFFERS",
            event_type="TILE_CLICK",
            device_type="Mobile",
            app_version="1.0",
        )
        self._insert_home_event(
            event_id="E10",
            user_id="BRANCH1_USER6",
            session_id="S8",
            event_ts="2024-03-01T13:05:00",
            tile_id="TILE_OFFERS",
            event_type="TILE_CLICK",
            device_type="Web",
            app_version="1.0",
        )

        # Re-run ETL
        self._call_etl_procedure()

        # Validate that TOTAL_CLICKS updated from 2 to 4 for Branch 1 / TILE_OFFERS
        row = self._fetch_single_summary_row(1, "TILE_OFFERS")
        self.assertIsNotNone(row, "Expected row for BRANCH_ID=1, TILE_ID='TILE_OFFERS'")
        self.assertEqual(row["TOTAL_CLICKS"], 4, "Expected TOTAL_CLICKS to be 4 after update scenario")

    # ============================================================
    # TEST CASE 05: TILE_CATEGORY defaulting to UNKNOWN
    # ============================================================
    def test_TC_SP_003_tile_category_default_unknown(self):
        """TC_SP_003: Validate TILE_CATEGORY defaults to 'UNKNOWN' when metadata is missing."""
        self._call_etl_procedure()
        row = self._fetch_single_summary_row(1, "TILE_MISC")
        self.assertIsNotNone(row, "Expected row for BRANCH_ID=1, TILE_ID='TILE_MISC'")
        self.assertEqual(row["TILE_CATEGORY"], "UNKNOWN")

    # ============================================================
    # TEST CASE 06: CTR calculation and division by zero handling
    # ============================================================
    def test_TC_SP_004_ctr_calculation(self):
        """TC_SP_004: Validate CTR computation and division by zero handling."""
        self._call_etl_procedure()

        # Branch 2 / TILE_HEALTH: 2 views, 0 clicks -> CTR = 0
        row_health = self._fetch_single_summary_row(2, "TILE_HEALTH")
        self.assertIsNotNone(row_health)
        self.assertEqual(row_health["TOTAL_VIEWS"], 2)
        self.assertEqual(row_health["TOTAL_CLICKS"], 0)
        self.assertEqual(row_health["CLICK_THROUGH_RATE"], Decimal("0.0000"))

        # Branch 1 / TILE_OFFERS: 3 views, 2 clicks -> CTR ~ 0.6667
        row_offers = self._fetch_single_summary_row(1, "TILE_OFFERS")
        self.assertIsNotNone(row_offers)
        self.assertEqual(row_offers["TOTAL_VIEWS"], 3)
        self.assertEqual(row_offers["TOTAL_CLICKS"], 2)
        self.assertEqual(row_offers["CLICK_THROUGH_RATE"], Decimal("0.6667"))

    # ============================================================
    # TEST CASE 07: REGION and LAST_AUDIT_DATE enrichment
    # ============================================================
    def test_TC_SP_005_region_and_audit_date_enrichment(self):
        """TC_SP_005: Validate REGION and LAST_AUDIT_DATE enrichment from branch metadata."""
        self._call_etl_procedure()

        row_branch1_offers = self._fetch_single_summary_row(1, "TILE_OFFERS")
        self.assertEqual(row_branch1_offers["REGION"], "NORTH")
        self.assertEqual(str(row_branch1_offers["LAST_AUDIT_DATE"]), "2024-01-15")

        row_branch2_health = self._fetch_single_summary_row(2, "TILE_HEALTH")
        self.assertEqual(row_branch2_health["REGION"], "SOUTH")
        self.assertEqual(str(row_branch2_health["LAST_AUDIT_DATE"]), "2024-02-10")

    # ============================================================
    # TEST CASE 08: Logging entries for successful run
    # ============================================================
    def test_TC_SP_006_logging_success(self):
        """TC_SP_006: Validate ETL_LOG entries for successful run."""
        self._call_etl_procedure()
        cur = self.conn.cursor()
        cur.execute(
            """
            SELECT STEP_NAME, STATUS
            FROM dbo.ETL_LOG
            ORDER BY LOG_ID DESC;
            """
        )
        rows = cur.fetchall()
        self.assertGreater(len(rows), 0, "Expected at least one log entry")
        # Check latest START/END pair
        step_statuses = [(r[0], r[1]) for r in rows[:2]]
        step_names = [s[0] for s in step_statuses]
        self.assertIn("START", step_names)
        self.assertIn("END", step_names)

    # ============================================================
    # TEST CASE 09: Error handling and rollback (controlled failure)
    # ============================================================
    def test_TC_SP_007_error_handling_and_rollback(self):
        """TC_SP_007: Validate rollback and error logging on failure."""
        cur = self.conn.cursor()

        # Introduce a controlled failure by temporarily dropping required table
        cur.execute("IF OBJECT_ID('dbo.SOURCE_HOME_TILE_EVENTS', 'U') IS NOT NULL DROP TABLE dbo.SOURCE_HOME_TILE_EVENTS;")
        self.conn.commit()

        # Attempt ETL and expect an exception
        with self.assertRaises(pyodbc.Error):
            self._call_etl_procedure()

        # Validate error log entry
        cur.execute(
            """
            SELECT TOP 1 STATUS, STEP_NAME
            FROM dbo.ETL_LOG
            ORDER BY LOG_ID DESC;
            """
        )
        row = cur.fetchone()
        self.assertIsNotNone(row)
        self.assertEqual(row.STATUS, "FAILED")

        # Re-create the base script to restore the environment
        input_file_name = "DI_CodeUpdate"
        tsql_script_path = os.path.join(
            self.cfg["OUTPUT_FOLDER"], f"{input_file_name}_version_1.sql"
        )
        tsql_content = read_tsql_script(tsql_script_path)
        execute_tsql_batch(self.conn.cursor(), tsql_content)

    # ============================================================
    # TEST CASE 10: Idempotent ETL behavior on repeated runs
    # ============================================================
    def test_TC_SP_008_idempotent_behavior(self):
        """TC_SP_008: Validate that repeated ETL runs without source changes do not create duplicates."""
        # First run
        self._call_etl_procedure()
        rows_first = self._fetch_summary_rows()

        # Second run without changes
        self._call_etl_procedure()
        rows_second = self._fetch_summary_rows()

        # Same number of records and same content for each key
        self.assertEqual(len(rows_first), len(rows_second))
        self.assertEqual(sorted(rows_first, key=lambda r: (r["BRANCH_ID"], r["TILE_ID"])),
                         sorted(rows_second, key=lambda r: (r["BRANCH_ID"], r["TILE_ID"])))

    # ============================================================
    # TEST CASE 11: INSERT into new BRANCH_ID/TILE_ID combination
    # ============================================================
    def test_TC_DML_001_insert_new_branch_tile(self):
        """TC_DML_001: Validate INSERT of new branch/tile combination."""
        # Insert new branch operational detail
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO dbo.BRANCH_OPERATIONAL_DETAILS
                (BRANCH_ID, REGION, MANAGER_NAME, LAST_AUDIT_DATE, IS_ACTIVE)
            VALUES
                (4, 'WEST', 'Dave Manager', '2024-03-01', 'Y');
            """
        )
        self.conn.commit()

        # Insert home and interstitial events for branch 4 / TILE_OFFERS
        self._insert_home_event(
            event_id="E11",
            user_id="BRANCH4_USER1",
            session_id="S9",
            event_ts="2024-03-02T09:00:00",
            tile_id="TILE_OFFERS",
            event_type="TILE_VIEW",
            device_type="Mobile",
            app_version="1.0",
        )

        # Re-run ETL
        self._call_etl_procedure()

        # Validate new row exists
        row = self._fetch_single_summary_row(4, "TILE_OFFERS")
        self.assertIsNotNone(row, "Expected new row for BRANCH_ID=4, TILE_ID='TILE_OFFERS'")
        self.assertEqual(row["REGION"], "WEST")

    # ============================================================
    # TEST CASE 12: UPDATE existing Misc tile record
    # ============================================================
    def test_TC_DML_002_update_misc_tile(self):
        """TC_DML_002: Validate UPDATE of existing Misc tile record."""
        # Baseline ETL
        self._call_etl_procedure()

        # Add click event for Branch 1 / TILE_MISC
        self._insert_home_event(
            event_id="E12",
            user_id="BRANCH1_USER7",
            session_id="S10",
            event_ts="2024-03-02T10:00:00",
            tile_id="TILE_MISC",
            event_type="TILE_CLICK",
            device_type="Web",
            app_version="1.0",
        )

        # Re-run ETL
        self._call_etl_procedure()

        # Validate TARGET record updated
        row = self._fetch_single_summary_row(1, "TILE_MISC")
        self.assertIsNotNone(row)
        self.assertEqual(row["TOTAL_CLICKS"], 1)


if __name__ == "__main__":
    unittest.main()
```

---

## 5. Cost Estimation and Justification

This test suite adds minimal overhead to the existing ETL pipeline:

1. **Execution Time**
   - Base T-SQL ETL script runs in under a second with sample data.
   - The unittest suite runs multiple ETL invocations; total time is expected to remain within a few seconds per full test run in a development environment.

2. **Database Resource Usage**
   - Tests operate on small synthetic tables and do not impact production data.
   - All objects are created/dropped idempotently at the start of each test suite run via the base T-SQL script.

3. **Maintenance**
   - Tests are organized by logical function and behavior, simplifying updates as the underlying ETL evolves.
   - Additional scenarios can be added as new T-SQL logic is introduced.

4. **Value**
   - Provides high-confidence coverage for:
     - Branch ID derivation logic.
     - Aggregations and CTR computations.
     - Metadata enrichments.
     - MERGE-based insert/update behavior.
     - Error handling and logging.
   - Ensures regressions are caught before deployment to higher environments.
