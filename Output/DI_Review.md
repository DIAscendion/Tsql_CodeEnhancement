```text
==================================================
Author: Ascendion AAVA
Date: 
Description: T-SQL review comparing branch_operational_details DDL against DI_CodeUpdate ETL artifact and highlighting structural/semantic/quality deltas
==================================================
```

## Summary of changes

### List of deviations (with file, line, and type)

> Line numbers for `Output/DI_CodeUpdate.md` are approximate based on the rendered markdown sections; validate against repository file viewer for exact positions.

| # | File | Line(s) | Type | Deviation |
|---:|------|--------:|------|----------|
| 1 | Input/branch_operational_details.sql | 1-8 | Structural | Source DDL is **Oracle-style** (`VARCHAR2`) and **no schema prefix**; DI_CodeUpdate implements **SQL Server** version with `NVARCHAR` and `dbo.` schema. |
| 2 | Input/branch_operational_details.sql | 1-8 | Semantic | Column nullability differs: Input DDL allows NULLs (no `NOT NULL`), while DI_CodeUpdate defines `BRANCH_ID`, `REGION`, `MANAGER_NAME`, `IS_ACTIVE` as `NOT NULL`. |
| 3 | Output/DI_CodeUpdate.md | ~120-170 | Structural | DI_CodeUpdate introduces an explicit SQL Server constraint name `PK_BRANCH_OPERATIONAL_DETAILS`; Input DDL uses unnamed `PRIMARY KEY (BRANCH_ID)`. |
| 4 | Output/DI_CodeUpdate.md | ~190-230 | Semantic | DI_CodeUpdate sample data assumes `REGION` and `MANAGER_NAME` are mandatory and always populated; Input DDL does not enforce this contract. |
| 5 | Output/DI_CodeUpdate.md | ~320-420 | Semantic | Branch ETL uses `INNER JOIN` from `BranchBase` to `BRANCH_OPERATIONAL_DETAILS` (effectively requires presence in details); however `BranchBase` is already derived from `BRANCH_OPERATIONAL_DETAILS`, making join redundant but harmless. |
| 6 | Output/DI_CodeUpdate.md | ~320-420 | Quality | `BranchBase` CTE uses a constant `10 AS total_transactions` (simulated). This is acceptable for test harness but should be flagged if this file is ever repurposed for production logic. |
| 7 | Output/DI_CodeUpdate.md | ~85-110 | Quality | Full object drops are executed unconditionally (idempotent but destructive). Appropriate for sandbox/tests only; risky in shared DBs. |
| 8 | Output/DI_CodeUpdate.md | ~240-420 | Quality | `MERGE` is used for upsert; in SQL Server, `MERGE` has known edge-case issues and concurrency caveats. Consider `UPDATE; IF @@ROWCOUNT=0 INSERT` pattern if productionized. |
| 9 | Output/DI_CodeUpdate.md | ~340-420 | Semantic | `is_active` in target table is loaded from `bb.IS_ACTIVE` (from details). Input DDL uses `IS_ACTIVE` `CHAR(1)` but no constraint on allowed values. DI assumes `Y/N` semantics. |
| 10 | Output/DI_CodeUpdate.md | ~330-420 | Structural | Target table `dbo.BRANCH_SUMMARY_REPORT` introduces `REGION` and `LAST_AUDIT_DATE` as nullable, but source table defines them as NOT NULL / NULL respectively in DI. Contract mismatch (REGION mandatory in DI source but optional in target). |

### Categorization_Changes: structural, semantic, quality with severity

| Category | Severity | Items | Notes |
|---|---:|---:|---|
| Structural | Medium | 1, 3, 10 | Data type and schema portability differences (Oracle vs SQL Server) are expected but must be explicit in migration docs. |
| Semantic | High | 2, 4, 5, 9 | Nullability and business contract assumptions (mandatory REGION/MANAGER_NAME/IS_ACTIVE) can change downstream behavior and load outcomes. |
| Quality | Medium | 6, 7, 8 | Test-only patterns are present in a primary artifact; MERGE and destructive drops require guardrails. |

## Detailed T-SQL comparison (focus: BRANCH_OPERATIONAL_DETAILS)

### 1) DDL differences

**Input/branch_operational_details.sql (Oracle-like):**
```sql
CREATE TABLE BRANCH_OPERATIONAL_DETAILS (
    BRANCH_ID INT,
    REGION VARCHAR2(50),
    MANAGER_NAME VARCHAR2(100),
    LAST_AUDIT_DATE DATE,
    IS_ACTIVE CHAR(1),
    PRIMARY KEY (BRANCH_ID)
);
```

**Output/DI_CodeUpdate.md (SQL Server test model):**
```sql
CREATE TABLE dbo.BRANCH_OPERATIONAL_DETAILS
(
    BRANCH_ID        INT            NOT NULL,
    REGION           NVARCHAR(50)   NOT NULL,
    MANAGER_NAME     NVARCHAR(100)  NOT NULL,
    LAST_AUDIT_DATE  DATE           NULL,
    IS_ACTIVE        CHAR(1)        NOT NULL,
    CONSTRAINT PK_BRANCH_OPERATIONAL_DETAILS PRIMARY KEY (BRANCH_ID)
);
```

**Key deltas:**
- **Dialect**: `VARCHAR2` → `NVARCHAR` (expected SQL Server port).
- **Schema**: none → `dbo.`.
- **Nullability**: unspecified (nullable in Oracle by default) → enforced `NOT NULL` on key business columns.
- **Constraint naming**: unnamed PK → named PK.

### 2) ETL semantics impacting branch data

**Branch load pattern (DI_CodeUpdate.md):**
- `BranchBase` is sourced from `dbo.BRANCH_OPERATIONAL_DETAILS`.
- `MERGE` loads `dbo.BRANCH_SUMMARY_REPORT` with enrichment columns `REGION`, `LAST_AUDIT_DATE`.
- `total_transactions` is hard-coded to `10` (simulated metric).

**Behavioral impacts vs input DDL contract:**
- If upstream allows NULL `REGION`/`MANAGER_NAME`/`IS_ACTIVE`, DI's SQL Server DDL would reject inserts.
- Target `BRANCH_SUMMARY_REPORT.REGION` is nullable, but DI assumes it is always present in source.

## Additional T-SQL Optimization Suggestions

1. **Guard destructive DDL**
   - Wrap DROP/CREATE blocks with an explicit `@IsTestRun` parameter or separate bootstrap script to prevent accidental execution in shared environments.

2. **Replace `MERGE` if productionizing**
   - Prefer an `UPDATE` followed by `INSERT` (or `INSERT...ON DUPLICATE` equivalent patterns) to avoid known `MERGE` caveats, especially under concurrency.

3. **Enforce allowed values for `IS_ACTIVE`**
   - Add a CHECK constraint in test model to mirror expected contract:
     ```sql
     ALTER TABLE dbo.BRANCH_OPERATIONAL_DETAILS
     ADD CONSTRAINT CK_BRANCH_OPERATIONAL_DETAILS_IS_ACTIVE
     CHECK (IS_ACTIVE IN ('Y','N'));
     ```

4. **Remove redundant join**
   - `BranchBase` already reads from `BRANCH_OPERATIONAL_DETAILS`; the subsequent `INNER JOIN` back to the same table can be removed (or change `BranchBase` to come from a different simulated transaction source).

5. **Indexing for realistic performance tests**
   - Add supporting indexes for ETL read patterns:
     - `BRANCH_OPERATIONAL_DETAILS(BRANCH_ID)` already covered by PK.
     - Consider `TILE_DAILY_SUMMARY(SummaryDate)` include columns if querying by date.

|||||| Cost Estimation and Justification

### 8.1 Development Effort

1. **T-SQL ETL design and implementation**
   - Schema design for test tables.
   - Tile and branch aggregation logic.
   - Metadata enrichment (`tile_category`, `REGION`, `LAST_AUDIT_DATE`).
   - Transaction and error handling.
   - Estimated: 1.5–2 person-days.

2. **Python test harness**
   - Connection management.
   - ETL invocation and validation.
   - Markdown reporting.
   - Estimated: 1 person-day.

3. **Self-healing pattern and documentation**
   - Versioning and metadata strategy.
   - Pipeline naming and governance.
   - Estimated: 0.5 person-day.

**Total development effort**: ~3.0–3.5 person-days.

### 8.2 Runtime / Infrastructure Cost

- SQL Server test environment (small DB): minimal compute/storage.
- Python execution (CI pipeline or job): negligible compared to production workloads.

Assuming standard cloud SQL pricing and CI agent cost, overall recurrent cost for this ETL unit test pipeline is low (fractions of a vCore and GBs of storage).

### 8.3 Justification

- The self-contained design avoids touching production data, reducing risk.
- Automated Python validation ensures repeatable, regression-safe deployments.
- The self-healing versioning pattern aligns with enterprise DevOps and audit needs.
```