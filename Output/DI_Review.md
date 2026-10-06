==================================================
Author: Ascendion AAVA
Date: 
Description: T-SQL comparison review between source DDL input and generated SQL Server ETL update document.
==================================================

## Read & Parse Input Files

### Files Parsed
- `Input/branch_operational_details.sql`
- `Output/DI_CodeUpdate.md`

### Parsed Objects (Baseline / Existing)
**File:** `Input/branch_operational_details.sql`
- **Object Type:** Table (DDL)
- **Object Name:** `BRANCH_OPERATIONAL_DETAILS`
- **Detected Dialect:** Oracle-style (`VARCHAR2`)
- **Definition (columns):**
  - `BRANCH_ID INT` (PK)
  - `REGION VARCHAR2(50)`
  - `MANAGER_NAME VARCHAR2(100)`
  - `LAST_AUDIT_DATE DATE`
  - `IS_ACTIVE CHAR(1)`

### Parsed Objects (Updated / Generated)
**File:** `Output/DI_CodeUpdate.md`
- **Object Types:**
  - Stored procedure: `dbo.sp_RunTestETL_V1`
  - Tables created/dropped (test harness):
    - `dbo.ETL_EXECUTION_LOG`
    - `dbo.SRC_HOME_TILE_EVENTS`
    - `dbo.SRC_INTERSTITIAL_EVENTS`
    - `dbo.SRC_TILE_METADATA`
    - `dbo.SRC_BRANCH_OPERATIONAL_DETAILS`
    - `dbo.TGT_TILE_EVENT_SUMMARY`
    - `dbo.TGT_BRANCH_SUMMARY_REPORT`
  - CTEs:
    - `HomeEvents`
    - `AggregatedEvents`
    - `InterstitialAgg`
  - Python harness included in markdown (non-T-SQL)

---

## Final T-SQL Comparison Output

### 1) Structural Changes

#### 1.1 Added SQL Server Objects (not present in baseline DDL)
**File:** `Output/DI_CodeUpdate.md`
- **(Added)** Stored procedure: `dbo.sp_RunTestETL_V1`
  - **Type:** Structural
  - **Severity:** Medium
  - **Notes:** Wraps entire ETL flow with TRY/CATCH and explicit transaction.

- **(Added)** Tables (test/source/target/log)
  - `dbo.ETL_EXECUTION_LOG` (logging)
  - `dbo.SRC_HOME_TILE_EVENTS` (test source)
  - `dbo.SRC_INTERSTITIAL_EVENTS` (test source)
  - `dbo.SRC_TILE_METADATA` (test source)
  - `dbo.SRC_BRANCH_OPERATIONAL_DETAILS` (SQL Server version of baseline table)
  - `dbo.TGT_TILE_EVENT_SUMMARY` (target aggregate)
  - `dbo.TGT_BRANCH_SUMMARY_REPORT` (target report)
  - **Type:** Structural
  - **Severity:** Medium
  - **Notes:** None of these exist in the baseline file; the baseline contains only a single DDL.

#### 1.2 Changed Definition: BRANCH_OPERATIONAL_DETAILS mapping to SQL Server staging table
**Baseline File:** `Input/branch_operational_details.sql`
- Table: `BRANCH_OPERATIONAL_DETAILS`

**Updated File:** `Output/DI_CodeUpdate.md`
- Table: `dbo.SRC_BRANCH_OPERATIONAL_DETAILS`

**Key structural deviations**
- **Name change:** `BRANCH_OPERATIONAL_DETAILS` → `SRC_BRANCH_OPERATIONAL_DETAILS`
- **Schema qualification:** none → `dbo.`
- **Datatype change:**
  - `REGION VARCHAR2(50)` → `REGION VARCHAR(50)`
  - `MANAGER_NAME VARCHAR2(100)` → `MANAGER_NAME VARCHAR(100)`
  - `LAST_AUDIT_DATE DATE` → `DATE` (same concept in SQL Server)
  - `IS_ACTIVE CHAR(1)` → `CHAR(1)` (same)
- **Constraint expression:**
  - Baseline: `PRIMARY KEY (BRANCH_ID)`
  - Updated: `BRANCH_ID INT NOT NULL PRIMARY KEY` (inline PK)

**Impact:**
- Mostly expected SQL dialect conversion; minimal functional difference.

---

### 2) Semantic / Logic Changes

#### 2.1 Scope shift: from single-table DDL to full ETL pipeline
**File:** `Input/branch_operational_details.sql` vs `Output/DI_CodeUpdate.md`
- Baseline defines only operational branch reference table.
- Updated introduces a full ETL job that aggregates tile events, enriches with metadata, and loads reporting tables.

**Severity:** High
**Reason:** Behavioral addition (data creation, transformation, and persistence) far beyond the baseline DDL.

#### 2.2 Transaction handling & error behavior added
**File:** `Output/DI_CodeUpdate.md`
- `BEGIN TRANSACTION` / `COMMIT` with `TRY/CATCH` and `ROLLBACK` on error.
- `THROW` rethrows error.

**Severity:** Medium
**Reason:** Introduces atomicity guarantees and failure semantics; can change caller expectations.

#### 2.3 Idempotency behavior: destructive rebuild of test tables
**File:** `Output/DI_CodeUpdate.md`
- Drops and recreates source and target tables each run.

**Severity:** Medium
**Reason:** In a real ETL this would destroy persisted results; acceptable only for test harness. Must be clearly separated from prod.

#### 2.4 Data transformation contract additions
**File:** `Output/DI_CodeUpdate.md`
- Adds computed metrics:
  - `views_count`, `clicks_count`, `ctr`
  - interstitial metrics (views/click flags)
- Adds enrichment column:
  - `tile_category` defaulting to `UNKNOWN` when no metadata.

**Severity:** Medium
**Reason:** Defines new downstream contract fields and defaulting logic.

#### 2.5 Branch report logic (pass-through)
**File:** `Output/DI_CodeUpdate.md`
- Loads `TGT_BRANCH_SUMMARY_REPORT` as a direct select from `SRC_BRANCH_OPERATIONAL_DETAILS`.

**Severity:** Low
**Reason:** No transformation beyond copy; but does materialize the data.

---

### 3) Quality / Maintainability Findings

#### 3.1 SQL Server compatibility issue in baseline input
**File:** `Input/branch_operational_details.sql`
- Uses `VARCHAR2` which is not T-SQL.

**Severity:** Low
**Recommendation:** Store SQL Server canonical DDL version separately or provide translation.

#### 3.2 Update scenario in Python harness conflicts with procedure design
**File:** `Output/DI_CodeUpdate.md` (Python section)
- Python "update scenario" seeds and modifies tables, but procedure drops/recreates tables on execution.

**Severity:** High
**Impact:** The test does not truly validate UPDATE/merge behavior; it validates only post-rebuild state.

**Recommendation:**
- Refactor procedure into steps (setup vs transform/load), or add parameters to skip drop/recreate.
- Implement `MERGE`/UPSERT into target tables for true update semantics.

#### 3.3 Missing schema/object existence guards for target inserts
**File:** `Output/DI_CodeUpdate.md`
- Target tables are dropped and recreated; inserts rely on that.

**Severity:** Low
**Recommendation:** In non-test contexts, replace with `CREATE TABLE IF NOT EXISTS` pattern (via `OBJECT_ID` checks) and avoid destructive DDL.

---

## Summary of Changes (Deviations with file, line, type)

> Line numbers are approximate because `DI_CodeUpdate.md` is markdown containing multiple code blocks.

| Deviation | File | Line (approx) | Type |
|---|---|---:|---|
| Baseline defines only `BRANCH_OPERATIONAL_DETAILS` DDL (Oracle types) | `Input/branch_operational_details.sql` | 1-8 | Structural |
| Added procedure `dbo.sp_RunTestETL_V1` with transaction and TRY/CATCH | `Output/DI_CodeUpdate.md` | ~70-260 | Structural/Semantic |
| Added logging table `dbo.ETL_EXECUTION_LOG` | `Output/DI_CodeUpdate.md` | ~95-120 | Structural |
| Added staging table `dbo.SRC_BRANCH_OPERATIONAL_DETAILS` (SQL Server translation) | `Output/DI_CodeUpdate.md` | ~160-185 | Structural |
| Added CTE-based aggregation and enrichment for tile events | `Output/DI_CodeUpdate.md` | ~230-330 | Semantic |
| Added target tables `dbo.TGT_TILE_EVENT_SUMMARY`, `dbo.TGT_BRANCH_SUMMARY_REPORT` | `Output/DI_CodeUpdate.md` | ~190-230 | Structural |
| Python update scenario undermined by table recreation in stored procedure | `Output/DI_CodeUpdate.md` | ~380-520 | Quality/Semantic |

---

## Categorization_Changes (structural, semantic, quality) with severity

### Structural
- Added stored procedure `dbo.sp_RunTestETL_V1` (**Medium**)
- Added multiple source/target/log tables (**Medium**)
- Renamed/mapped baseline table to `dbo.SRC_BRANCH_OPERATIONAL_DETAILS` and converted datatypes (**Low**)

### Semantic
- Shift from reference DDL to full ETL + aggregation pipeline (**High**)
- Added transaction + error handling semantics (**Medium**)
- Added defaulting rule for `tile_category` (`UNKNOWN`) (**Medium**)

### Quality
- Input file not SQL Server native (`VARCHAR2`) (**Low**)
- Test harness update scenario is logically inconsistent with idempotent rebuild (**High**)

---

## Additional T-SQL Optimization Suggestions

1. **Implement UPSERT for targets instead of drop/recreate**
   - Use `MERGE dbo.TGT_TILE_EVENT_SUMMARY AS tgt` keyed by `(event_date, tile_id)`.

2. **Add indexes for aggregation/join performance (if scaled beyond test)**
   - `SRC_HOME_TILE_EVENTS(event_ts, tile_id, event_type)`
   - `SRC_INTERSTITIAL_EVENTS(event_ts, tile_id)`
   - `SRC_TILE_METADATA(tile_id)` already PK.

3. **Persist ETL execution metadata with consistent keys**
   - Add `RunID UNIQUEIDENTIFIER DEFAULT NEWID()` and store it across steps.

4. **Avoid VARCHAR for IDs if numeric**
   - If `tile_id` is numeric, store as INT/BIGINT. (If alphanumeric, keep VARCHAR.)

5. **CTR precision and divide-by-zero handling**
   - Current logic is safe; consider `NULLIF(AE.views_count,0)` to simplify.

---

|||||| Cost Estimation and Justification

(Calculation steps remain unchanged)

Assuming a typical data engineering environment, the effort includes:

1. **Analysis & Design (4–6 hours)**
   - Review Jira ticket TCU-1 and Confluence documentation.
   - Analyze existing DDLs and mapping.
   - Design SQL Server test harness and ETL logic.

2. **Implementation (6–8 hours)**
   - Develop T-SQL ETL procedure and test tables.
   - Implement Python-based test harness (no PyTest) with insert/update scenarios.
   - Add logging, error handling, and reporting.

3. **Testing & Self-Healing (4–6 hours)**
   - Execute Version 1.
   - Capture errors, refine ETL and tests as needed for Version 2/3.
   - Validate metrics, schema alignment, and edge cases.

4. **Documentation (2–3 hours)**
   - Prepare markdown report (this document).
   - Update lineage and dictionary (outside this file).

Total estimated effort: **16–23 hours** depending on environment setup, data volume, and integration complexity.
