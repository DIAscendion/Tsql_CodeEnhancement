=============================================
Author: Ascendion AAVA
Date: 
Description: Data model evolution package capturing schema deltas, T-SQL change scripts, impact analysis, and documentation for tile metadata and branch operational reporting enhancements.
=============================================

# Data Model Evolution Package

## 1. Delta Summary Report

### Overview
This data model evolution package compares the supplied source DDL inputs and technical specification requirements from JIRA ticket `TCU-1` and Confluence content against the currently available logical reporting model.

The requested enhancement introduces two primary model changes:
1. Addition of enrichment metadata from `analytics_db.SOURCE_TILE_METADATA` into tile reporting outputs.
2. Addition of operational branch context from `BRANCH_OPERATIONAL_DETAILS` into `BRANCH_SUMMARY_REPORT`.

Because no standalone existing T-SQL target DDL for the reporting tables was provided, the delta is computed against the available logical target definitions inferred from the technical specification.

### Overall Impact Level
- **Overall impact:** High
- **Version bump recommendation:** Minor if additive-only deployment is used and downstream consumers tolerate new nullable/defaulted columns; Major if strict schema contracts, schema-bound dependencies, or positional file consumers are affected.

### Change Categories

#### Additions
1. **New source table registered**: `analytics_db.SOURCE_TILE_METADATA`
2. **New target/reporting column**: `tile_category` in logical target `analytics_db.TARGET_TILE_DAILY_SUMMARY`
3. **New target/reporting columns** in `analytics_db.BRANCH_SUMMARY_REPORT`:
   - `REGION`
   - `LAST_AUDIT_DATE`
4. **New enrichment joins** in ETL logic:
   - Tile summary pipeline joins `SOURCE_TILE_METADATA` on `tile_id`
   - Branch summary pipeline joins `BRANCH_OPERATIONAL_DETAILS` on `BRANCH_ID`
5. **New defaulting rules**:
   - `tile_category = 'UNKNOWN'` when metadata missing/blank
   - `REGION = 'UNKNOWN'` when branch operational detail missing/blank

#### Modifications
1. **Tile reporting transformation logic** updated to project `tile_category`
2. **Tile target load logic** updated for `INSERT`/`MERGE` to include `tile_category`
3. **Branch summary load process** updated to perform full reload and include new enrichment columns
4. **Validation suite** updated to include null/default, duplication, and schema checks
5. **Data dictionary** updated to document new source and target attributes

#### Deprecations
- No explicit deprecations detected from supplied inputs.
- No columns, keys, constraints, or tables are requested to be dropped.

### Detailed Delta Matrix

| Object | Delta Type | Change | Impact | Risk |
|---|---|---|---|---|
| `analytics_db.SOURCE_TILE_METADATA` | Addition | New source metadata table | High | Source dependency introduction |
| `analytics_db.TARGET_TILE_DAILY_SUMMARY` | Modification | Add `tile_category` column | High | Downstream schema contract impact |
| Tile ETL/stored procedure/view | Modification | Add `LEFT JOIN` to metadata and default logic | High | Duplicate-row risk if metadata not unique |
| `BRANCH_SUMMARY_REPORT` | Modification | Add `REGION`, `LAST_AUDIT_DATE` | High | Downstream schema change |
| Branch reload logic | Modification | Switch/retain full reload pattern | Medium | Longer load windows |
| Validation scripts | Modification | Add schema/default/duplicate checks | Medium | Test suite drift if omitted |
| Documentation/lineage | Modification | Add metadata and mappings | Medium | Governance inconsistency if omitted |

### Risk Notes

#### Data loss risk
- **Low** for additive schema changes.
- **Medium** if deployment uses table recreation without preserving historical data.
- **Medium** if rollback drops newly populated columns after business adoption.

#### Key impact risk
- **Medium to High** because enrichment joins can duplicate output rows if source uniqueness is not enforced.
- `SOURCE_TILE_METADATA.tile_id` must be logically unique or deduplicated using latest-record rules.
- `BRANCH_OPERATIONAL_DETAILS.BRANCH_ID` is defined as primary key, reducing join duplication risk.

#### Downstream break risk
- **High** for views, stored procedures, ETL jobs, semantic models, and APIs expecting fixed schemas.
- **High** if SQL Server schema-bound views, indexed views, or strongly typed ingestion contracts depend on target objects.

#### SQL Server / T-SQL caveats
Although source examples include Databricks Delta and Oracle-style DDL, the target evolution package is expressed in T-SQL-compatible deployment form. Review the following before implementation:
- Adding non-null columns to populated SQL Server tables requires default/backfill handling.
- Schema-bound views/functions must be refreshed or altered before underlying schema changes.
- Indexed views may require drop/recreate or dependency-aware deployment.
- If branch report table participates in replication, CDC, temporal tables, or partition switching, DDL ordering must be adjusted.
- If target tables use clustered columnstore or partitioning, index maintenance/rebuild may be required after structural changes.

---

## 2. Existing vs Desired Model

### 2.1 Existing Logical Model Snapshot
Based on supplied inputs, the existing logical reporting flows can be represented as:

#### Tile reporting
- Source events:
  - `analytics_db.SOURCE_HOME_TILE_EVENTS`
  - `analytics_db.SOURCE_INTERSTITIAL_EVENTS`
- Existing logical target summary:
  - `analytics_db.TARGET_TILE_DAILY_SUMMARY`
- Existing summarized grain:
  - `event_date`, `tile_id`
- Existing measures:
  - `tile_views`
  - `tile_clicks`
  - `interstitial_views`
  - `primary_cta_clicks`
  - `secondary_cta_clicks`
  - `ctr`

#### Branch reporting
- Existing logical base source:
  - `BRANCH_BASE_SUMMARY`
- Existing logical target:
  - `analytics_db.BRANCH_SUMMARY_REPORT`
- Existing output enriched now with:
  - `REGION`
  - `LAST_AUDIT_DATE`

### 2.2 Desired Logical Model Snapshot

#### Target: `analytics_db.TARGET_TILE_DAILY_SUMMARY`
| Column | Type | Status | Rule |
|---|---|---|---|
| `event_date` | DATE | Existing | No change |
| `tile_id` | STRING/VARCHAR | Existing | No change |
| `tile_category` | STRING/VARCHAR | New | Default `UNKNOWN` if missing/blank |
| `tile_views` | BIGINT | Existing | No change |
| `tile_clicks` | BIGINT | Existing | No change |
| `interstitial_views` | BIGINT | Existing | No change |
| `primary_cta_clicks` | BIGINT | Existing | No change |
| `secondary_cta_clicks` | BIGINT | Existing | No change |
| `ctr` | DECIMAL(18,4) | Existing | No change |

#### Target: `analytics_db.BRANCH_SUMMARY_REPORT`
| Column | Type | Status | Rule |
|---|---|---|---|
| `BRANCH_ID` | INT | Existing | No change |
| `BRANCH_NAME` | VARCHAR | Existing | No change |
| `REPORT_DATE` | DATE | Existing | No change |
| `REGION` | VARCHAR(50) | New | Default `UNKNOWN` if missing/blank |
| `LAST_AUDIT_DATE` | DATE | New | Preserve date semantics |
| `TOTAL_ACCOUNTS` | Numeric | Existing | No change |
| `TOTAL_BALANCE` | Numeric | Existing | No change |

---

## 3. Forward DDL Change Scripts

> Note: Exact physical target DDLs were not supplied. The following scripts are generated as implementation-ready T-SQL templates and should be aligned to actual SQL Server schema names, constraints, and dependency objects before execution.

### 3.1 Forward DDL: Tile Reporting Enhancement

```sql
/*
Change: Add tile_category to target reporting table
Reason: JIRA TCU-1 requires category-level reporting enrichment from SOURCE_TILE_METADATA
Tech Spec Ref: JIRA TCU-1 / Section Tile Reporting Pipeline Changes
Impact: Additive schema evolution
*/

IF COL_LENGTH('analytics_db.TARGET_TILE_DAILY_SUMMARY', 'tile_category') IS NULL
BEGIN
    ALTER TABLE analytics_db.TARGET_TILE_DAILY_SUMMARY
    ADD tile_category VARCHAR(100) NULL;
END;
GO

/*
Optional backfill/default normalization
Reason: Preserve backward compatibility for existing rows
*/
UPDATE analytics_db.TARGET_TILE_DAILY_SUMMARY
SET tile_category = 'UNKNOWN'
WHERE tile_category IS NULL
   OR LTRIM(RTRIM(tile_category)) = '';
GO

/*
Optional hardening step if business requires non-null contract after backfill
Execute only after validating all upstream writes populate the column.
*/
-- ALTER TABLE analytics_db.TARGET_TILE_DAILY_SUMMARY
-- ALTER COLUMN tile_category VARCHAR(100) NOT NULL;
-- GO
```

### 3.2 Forward DDL: Branch Summary Enhancement

```sql
/*
Change: Add REGION and LAST_AUDIT_DATE to BRANCH_SUMMARY_REPORT
Reason: Confluence branch enhancement requires operational context enrichment
Tech Spec Ref: Confluence ETL Change - Integration of BRANCH_OPERATIONAL_DETAILS into BRANCH_SUMMARY_REPORT
Impact: Additive schema evolution
*/

IF COL_LENGTH('analytics_db.BRANCH_SUMMARY_REPORT', 'REGION') IS NULL
BEGIN
    ALTER TABLE analytics_db.BRANCH_SUMMARY_REPORT
    ADD REGION VARCHAR(50) NULL;
END;
GO

IF COL_LENGTH('analytics_db.BRANCH_SUMMARY_REPORT', 'LAST_AUDIT_DATE') IS NULL
BEGIN
    ALTER TABLE analytics_db.BRANCH_SUMMARY_REPORT
    ADD LAST_AUDIT_DATE DATE NULL;
END;
GO

/*
Optional normalization for existing rows
*/
UPDATE analytics_db.BRANCH_SUMMARY_REPORT
SET REGION = 'UNKNOWN'
WHERE REGION IS NULL
   OR LTRIM(RTRIM(REGION)) = '';
GO
```

### 3.3 ETL/Load Logic Change: Tile Reporting

```sql
/*
Change: Enrich tile summary with tile_category
Reason: Business requires functional grouping in reporting outputs
Tech Spec Ref: JIRA TCU-1
*/

WITH tile_events AS (
    SELECT
        CAST(event_ts AS DATE) AS event_date,
        tile_id,
        SUM(CASE WHEN event_type = 'TILE_VIEW'  THEN 1 ELSE 0 END) AS tile_views,
        SUM(CASE WHEN event_type = 'TILE_CLICK' THEN 1 ELSE 0 END) AS tile_clicks
    FROM analytics_db.SOURCE_HOME_TILE_EVENTS
    GROUP BY CAST(event_ts AS DATE), tile_id
),
interstitial_events AS (
    SELECT
        CAST(event_ts AS DATE) AS event_date,
        tile_id,
        SUM(CASE WHEN interstitial_view_flag = 1 THEN 1 ELSE 0 END) AS interstitial_views,
        SUM(CASE WHEN primary_button_click_flag = 1 THEN 1 ELSE 0 END) AS primary_cta_clicks,
        SUM(CASE WHEN secondary_button_click_flag = 1 THEN 1 ELSE 0 END) AS secondary_cta_clicks
    FROM analytics_db.SOURCE_INTERSTITIAL_EVENTS
    GROUP BY CAST(event_ts AS DATE), tile_id
),
metadata_dedup AS (
    SELECT tile_id, tile_category
    FROM (
        SELECT
            m.tile_id,
            m.tile_category,
            ROW_NUMBER() OVER (
                PARTITION BY m.tile_id
                ORDER BY m.updated_ts DESC
            ) AS rn
        FROM analytics_db.SOURCE_TILE_METADATA m
    ) d
    WHERE d.rn = 1
),
final_summary AS (
    SELECT
        t.event_date,
        t.tile_id,
        COALESCE(NULLIF(LTRIM(RTRIM(md.tile_category)), ''), 'UNKNOWN') AS tile_category,
        t.tile_views,
        t.tile_clicks,
        COALESCE(i.interstitial_views, 0) AS interstitial_views,
        COALESCE(i.primary_cta_clicks, 0) AS primary_cta_clicks,
        COALESCE(i.secondary_cta_clicks, 0) AS secondary_cta_clicks,
        CASE
            WHEN t.tile_views = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(t.tile_clicks AS DECIMAL(18,4)) / CAST(t.tile_views AS DECIMAL(18,4))
        END AS ctr
    FROM tile_events t
    LEFT JOIN interstitial_events i
        ON t.event_date = i.event_date
       AND t.tile_id = i.tile_id
    LEFT JOIN metadata_dedup md
        ON t.tile_id = md.tile_id
)
MERGE analytics_db.TARGET_TILE_DAILY_SUMMARY AS tgt
USING final_summary AS src
    ON tgt.event_date = src.event_date
   AND tgt.tile_id = src.tile_id
WHEN MATCHED THEN
    UPDATE SET
        tgt.tile_category = src.tile_category,
        tgt.tile_views = src.tile_views,
        tgt.tile_clicks = src.tile_clicks,
        tgt.interstitial_views = src.interstitial_views,
        tgt.primary_cta_clicks = src.primary_cta_clicks,
        tgt.secondary_cta_clicks = src.secondary_cta_clicks,
        tgt.ctr = src.ctr
WHEN NOT MATCHED THEN
    INSERT
    (
        event_date,
        tile_id,
        tile_category,
        tile_views,
        tile_clicks,
        interstitial_views,
        primary_cta_clicks,
        secondary_cta_clicks,
        ctr
    )
    VALUES
    (
        src.event_date,
        src.tile_id,
        src.tile_category,
        src.tile_views,
        src.tile_clicks,
        src.interstitial_views,
        src.primary_cta_clicks,
        src.secondary_cta_clicks,
        src.ctr
    );
GO
```

### 3.4 ETL/Load Logic Change: Branch Reporting

```sql
/*
Change: Full reload branch summary with operational enrichment
Reason: Confluence requirement for regulatory reporting enrichment
Tech Spec Ref: Branch operational details integration
*/

TRUNCATE TABLE analytics_db.BRANCH_SUMMARY_REPORT;
GO

INSERT INTO analytics_db.BRANCH_SUMMARY_REPORT
(
    BRANCH_ID,
    BRANCH_NAME,
    REPORT_DATE,
    REGION,
    LAST_AUDIT_DATE,
    TOTAL_ACCOUNTS,
    TOTAL_BALANCE
)
SELECT
    b.BRANCH_ID,
    b.BRANCH_NAME,
    CAST(b.REPORT_DATE AS DATE) AS REPORT_DATE,
    COALESCE(NULLIF(LTRIM(RTRIM(o.REGION)), ''), 'UNKNOWN') AS REGION,
    CAST(o.LAST_AUDIT_DATE AS DATE) AS LAST_AUDIT_DATE,
    b.TOTAL_ACCOUNTS,
    b.TOTAL_BALANCE
FROM analytics_db.BRANCH_BASE_SUMMARY b
LEFT JOIN analytics_db.BRANCH_OPERATIONAL_DETAILS o
    ON b.BRANCH_ID = o.BRANCH_ID;
GO
```

### 3.5 Optional Supporting Index Recommendations

```sql
/*
Recommended nonclustered index to support tile metadata join if target platform is SQL Server
*/
-- CREATE NONCLUSTERED INDEX IX_SOURCE_TILE_METADATA_TILE_ID
-- ON analytics_db.SOURCE_TILE_METADATA (tile_id);
-- GO

/*
Recommended nonclustered index to support branch detail join
*/
-- CREATE NONCLUSTERED INDEX IX_BRANCH_OPERATIONAL_DETAILS_BRANCH_ID
-- ON analytics_db.BRANCH_OPERATIONAL_DETAILS (BRANCH_ID);
-- GO
```

---

## 4. Rollback Scripts

> Rollback should be executed only if business confirms no dependency has adopted the new columns.

### 4.1 Rollback: Tile Reporting Column

```sql
/* Rollback for tile_category addition */
IF COL_LENGTH('analytics_db.TARGET_TILE_DAILY_SUMMARY', 'tile_category') IS NOT NULL
BEGIN
    ALTER TABLE analytics_db.TARGET_TILE_DAILY_SUMMARY
    DROP COLUMN tile_category;
END;
GO
```

### 4.2 Rollback: Branch Reporting Columns

```sql
/* Rollback for REGION and LAST_AUDIT_DATE additions */
IF COL_LENGTH('analytics_db.BRANCH_SUMMARY_REPORT', 'LAST_AUDIT_DATE') IS NOT NULL
BEGIN
    ALTER TABLE analytics_db.BRANCH_SUMMARY_REPORT
    DROP COLUMN LAST_AUDIT_DATE;
END;
GO

IF COL_LENGTH('analytics_db.BRANCH_SUMMARY_REPORT', 'REGION') IS NOT NULL
BEGIN
    ALTER TABLE analytics_db.BRANCH_SUMMARY_REPORT
    DROP COLUMN REGION;
END;
GO
```

### 4.3 Rollback Considerations
- If downstream views/procedures were altered to reference new columns, reverse those changes first.
- If historical data has been backfilled or reports now depend on these columns, rollback may create reporting inconsistencies.
- If audit evidence depends on `LAST_AUDIT_DATE`, rollback may violate traceability expectations.

---

## 5. Zero-Downtime / Minimally Disruptive Deployment Strategy

Where strict uptime is required, consider this staged approach:
1. Add nullable columns first.
2. Deploy ETL changes to begin populating the new columns.
3. Backfill existing rows where required.
4. Update dependent views and semantic layers.
5. Validate counts and duplicate checks.
6. Optionally enforce non-null constraints later.

For larger tables, an alternative controlled pattern is:
- `SELECT INTO` shadow table with evolved schema
- `INSERT ... SELECT` backfill and validation
- `sp_rename` cutover
- Recreate indexes, constraints, permissions, and statistics

Use this pattern when:
- schema-bound dependencies must be cut over together
- clustered index/key changes are required
- rollback speed is critical

---

## 6. Impact Assessment

### 6.1 Downstream Object Impact

| Object Category | Impact | Assessment |
|---|---|---|
| Views | Medium/High | Views exposing `SELECT *` will change shape automatically; explicit projections may need alteration |
| Stored procedures | High | Insert lists, merge statements, temp tables, and variable mappings may require updates |
| Functions | Medium | Table-valued functions returning target schema may need modification |
| Triggers | Low/Medium | Only impacted if target tables have DML triggers referencing inserted/deleted schemas |
| ETL jobs | High | Schema validations and mapping logic require updates |
| APIs / extracts | High | Consumers expecting fixed output columns may break or ignore additions |
| Reports / dashboards | Medium | Semantic layer must expose new fields intentionally |
| Data quality checks | High | Null/default/duplicate assertions must be added |

### 6.2 Foreign Key / Relationship Ripple Effects
- No explicit new foreign keys were supplied.
- Logical relationships introduced:
  - `SOURCE_HOME_TILE_EVENTS.tile_id` → `SOURCE_TILE_METADATA.tile_id`
  - `SOURCE_INTERSTITIAL_EVENTS.tile_id` → `SOURCE_TILE_METADATA.tile_id`
  - `BRANCH_BASE_SUMMARY.BRANCH_ID` → `BRANCH_OPERATIONAL_DETAILS.BRANCH_ID`
- Recommend logical uniqueness validation on metadata rather than immediate physical FK enforcement if source freshness is variable.

### 6.3 Data Quality Risks
1. Duplicate `tile_id` in metadata could multiply summary rows.
2. Blank `tile_category` or `REGION` values may bypass null checks unless normalized.
3. Oracle date ingestion for `LAST_AUDIT_DATE` may need explicit conversion and timezone/date handling validation.
4. Full reload branch process may create temporary data unavailability if not wrapped in transactional or shadow-table deployment.

### 6.4 Compatibility / Governance Notes
- Add lineage from JIRA `TCU-1` and Confluence requirement into governance metadata.
- Ensure data dictionary records defaulting semantics for `UNKNOWN` values.
- If SQL Server compatibility level differs across environments, validate `TRIM` availability; `LTRIM(RTRIM())` is used here for broader compatibility.

---

## 7. Data Model Documentation

### 7.1 Annotated Dictionary: New / Changed Columns

#### `analytics_db.TARGET_TILE_DAILY_SUMMARY`
| Column | Type | Nullable | Change Type | Default / Rule | Source | Description |
|---|---|---:|---|---|---|---|
| `tile_category` | VARCHAR(100) | Yes initially, recommended No after stabilization | Added | `COALESCE(NULLIF(LTRIM(RTRIM(tile_category)), ''), 'UNKNOWN')` | `analytics_db.SOURCE_TILE_METADATA.tile_category` | Functional/business category of tile for enriched reporting |

#### `analytics_db.BRANCH_SUMMARY_REPORT`
| Column | Type | Nullable | Change Type | Default / Rule | Source | Description |
|---|---|---:|---|---|---|---|
| `REGION` | VARCHAR(50) | Yes | Added | `COALESCE(NULLIF(LTRIM(RTRIM(REGION)), ''), 'UNKNOWN')` | `BRANCH_OPERATIONAL_DETAILS.REGION` | Branch regional classification for audit/reporting context |
| `LAST_AUDIT_DATE` | DATE | Yes | Added | Direct mapped cast to `DATE` | `BRANCH_OPERATIONAL_DETAILS.LAST_AUDIT_DATE` | Most recent audit date for branch operational oversight |

### 7.2 New Source Entity Documentation

#### `analytics_db.SOURCE_TILE_METADATA`
| Column | Data Type | Nullable | Key Role | Change Metadata |
|---|---|---:|---|---|
| `tile_id` | STRING / VARCHAR | Yes in source DDL | Business join key | New source object used for enrichment |
| `tile_name` | STRING / VARCHAR | Yes | Descriptive attribute | New source attribute |
| `tile_category` | STRING / VARCHAR | Yes | Enrichment attribute | New attribute propagated to target |
| `is_active` | BOOLEAN / BIT | Yes | Status attribute | Optional business filter |
| `updated_ts` | TIMESTAMP / DATETIME2 | Yes | Latest-record ordering attribute | Supports dedup/version resolution |

#### `BRANCH_OPERATIONAL_DETAILS`
| Column | Data Type | Nullable | Key Role | Change Metadata |
|---|---|---:|---|---|
| `BRANCH_ID` | INT | No | Primary key | Source join key |
| `REGION` | VARCHAR2(50) / VARCHAR(50) | Yes | Enrichment attribute | Propagated to target |
| `MANAGER_NAME` | VARCHAR2(100) | Yes | Informational attribute | Not currently propagated |
| `LAST_AUDIT_DATE` | DATE | Yes | Enrichment attribute | Propagated to target |
| `IS_ACTIVE` | CHAR(1) | Yes | Status attribute | Optional future filter |

---

## 8. Before vs After Model Diff

### 8.1 Tile Reporting Diff

| Attribute | Before | After |
|---|---|---|
| Source enrichment table | Not present | `analytics_db.SOURCE_TILE_METADATA` added |
| Tile reporting dimension | `tile_id` only | `tile_id` + `tile_category` |
| Missing metadata handling | Not applicable | Default to `UNKNOWN` |
| Target schema | No `tile_category` | `tile_category` added |
| Duplicate protection | Not required | Required via metadata dedup/uniqueness validation |

### 8.2 Branch Reporting Diff

| Attribute | Before | After |
|---|---|---|
| Operational branch context | Not exposed | `REGION`, `LAST_AUDIT_DATE` exposed |
| Source join | Base summary only | Base summary + operational details |
| Load mode | Existing unspecified | Full reload required |
| Missing region handling | Not applicable | Default to `UNKNOWN` |

---

## 9. Validation SQL / Data Quality Checks

### 9.1 Tile Validation

```sql
/* Ensure target column exists */
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'analytics_db'
  AND TABLE_NAME = 'TARGET_TILE_DAILY_SUMMARY'
  AND COLUMN_NAME = 'tile_category';
GO

/* Ensure no null categories after load */
SELECT COUNT(*) AS null_tile_category_count
FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
WHERE tile_category IS NULL;
GO

/* Detect blank categories after normalization */
SELECT COUNT(*) AS blank_tile_category_count
FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
WHERE LTRIM(RTRIM(tile_category)) = '';
GO

/* Detect duplicate metadata keys */
SELECT tile_id, COUNT(*) AS cnt
FROM analytics_db.SOURCE_TILE_METADATA
GROUP BY tile_id
HAVING COUNT(*) > 1;
GO

/* Check target grain remains unique */
SELECT event_date, tile_id, COUNT(*) AS cnt
FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
GROUP BY event_date, tile_id
HAVING COUNT(*) > 1;
GO
```

### 9.2 Branch Validation

```sql
/* Ensure new branch columns exist */
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'analytics_db'
  AND TABLE_NAME = 'BRANCH_SUMMARY_REPORT'
  AND COLUMN_NAME IN ('REGION', 'LAST_AUDIT_DATE');
GO

/* Validate region normalization */
SELECT COUNT(*) AS null_region_count
FROM analytics_db.BRANCH_SUMMARY_REPORT
WHERE REGION IS NULL;
GO

/* Check branch grain duplication after join */
SELECT BRANCH_ID, REPORT_DATE, COUNT(*) AS cnt
FROM analytics_db.BRANCH_SUMMARY_REPORT
GROUP BY BRANCH_ID, REPORT_DATE
HAVING COUNT(*) > 1;
GO
```

---

## 10. Traceability Matrix

| Tech Spec Source | Requirement | Data Model Change | DDL / Logic Reference |
|---|---|---|---|
| JIRA `TCU-1` | Add new source table `SOURCE_TILE_METADATA` | New source object registered and used in enrichment | Tile ETL logic section / source entity documentation |
| JIRA `TCU-1` | Add `tile_category` to target reporting output | New target column in `TARGET_TILE_DAILY_SUMMARY` | Forward DDL 3.1 |
| JIRA `TCU-1` | Backward compatibility with `UNKNOWN` default | Defaulting logic in ETL and backfill | Forward DDL 3.1 and ETL 3.3 |
| Confluence branch enhancement | Integrate `BRANCH_OPERATIONAL_DETAILS` | New source-to-target branch join | ETL 3.4 |
| Confluence branch enhancement | Add `REGION`, `LAST_AUDIT_DATE` to `BRANCH_SUMMARY_REPORT` | Two new target columns | Forward DDL 3.2 |
| Confluence branch enhancement | Full reload deployment | Truncate and reload branch target | ETL 3.4 |

---

## 11. Visual Relationship Diagrams

### Tile Reporting
```text
+-------------------------------------------+
| analytics_db.SOURCE_HOME_TILE_EVENTS      |
|-------------------------------------------|
| event_id                                  |
| user_id                                   |
| session_id                                |
| event_ts                                  |
| tile_id                                   |----+
| event_type                                |    |
| device_type                               |    |
| app_version                               |    |
+-------------------------------------------+    |
                                                   |
                                                   v
+-------------------------------------------+   +--------------------------------------+
| analytics_db.SOURCE_INTERSTITIAL_EVENTS   |   | analytics_db.SOURCE_TILE_METADATA    |
|-------------------------------------------|   |--------------------------------------|
| event_id                                  |   | tile_id                             |
| user_id                                   |   | tile_name                           |
| session_id                                |   | tile_category                       |
| event_ts                                  |   | is_active                           |
| tile_id                                   |---| updated_ts                          |
| interstitial_view_flag                    |   +--------------------------------------+
| primary_button_click_flag                 |
| secondary_button_click_flag               |
+-------------------------------------------+
                  |
                  v
+--------------------------------------------------+
| analytics_db.TARGET_TILE_DAILY_SUMMARY           |
|--------------------------------------------------|
| event_date                                       |
| tile_id                                          |
| tile_category                                    |
| tile_views                                       |
| tile_clicks                                      |
| interstitial_views                               |
| primary_cta_clicks                               |
| secondary_cta_clicks                             |
| ctr                                              |
+--------------------------------------------------+
```

### Branch Reporting
```text
+----------------------------------+       +--------------------------------------+
| BRANCH_BASE_SUMMARY              |       | BRANCH_OPERATIONAL_DETAILS           |
|----------------------------------|       |--------------------------------------|
| BRANCH_ID                        |-------| BRANCH_ID (PK)                       |
| BRANCH_NAME                      |       | REGION                               |
| REPORT_DATE                      |       | MANAGER_NAME                         |
| TOTAL_ACCOUNTS                   |       | LAST_AUDIT_DATE                      |
| TOTAL_BALANCE                    |       | IS_ACTIVE                            |
+----------------------------------+       +--------------------------------------+
                    |
                    v
+--------------------------------------------------+
| analytics_db.BRANCH_SUMMARY_REPORT               |
|--------------------------------------------------|
| BRANCH_ID                                        |
| BRANCH_NAME                                      |
| REPORT_DATE                                      |
| REGION                                           |
| LAST_AUDIT_DATE                                  |
| TOTAL_ACCOUNTS                                   |
| TOTAL_BALANCE                                    |
+--------------------------------------------------+
```

---

## 12. Assumptions, Constraints, and Audit Notes

### Assumptions
- Existing target object names are logical placeholders where physical DDL was not provided.
- SQL Server-compatible deployment is required even though source examples include Databricks and Oracle syntax.
- `analytics_db` is treated as the effective target schema name as referenced in the inputs.
- Metadata uniqueness is enforced logically if not physically constrained.

### Constraints
- Backward compatibility must be preserved.
- Existing counts and KPIs must remain unchanged.
- Branch summary deployment requires full reload.
- Historical backfill beyond defaulting existing rows is out of scope unless separately approved.

### Auditability Notes
- Source requirements trace to JIRA `TCU-1` and Confluence branch integration note.
- Forward and rollback scripts are included for controlled deployment.
- Change rationale is embedded in DDL comments.
- Validation steps support post-deployment evidence capture.

---

## 13. Cost Estimation and Justification

Actual token usage, runtime model identity, and pricing metadata are not exposed through the available tools in this environment.
Therefore, an exact numeric execution cost cannot be calculated reliably from system-provided telemetry.

### Available Status
- **Model used:** Not programmatically exposed in available tool context
- **Total input tokens:** Not programmatically exposed
- **Total output tokens:** Not programmatically exposed
- **Input token price:** Not programmatically exposed
- **Output token price:** Not programmatically exposed

### Formula
```text
Input Cost  = input_tokens  × input_cost_per_token
Output Cost = output_tokens × output_cost_per_token
Total Cost  = Input Cost + Output Cost
```

### Current Result
```text
Input Cost  = TBD
Output Cost = TBD
Total Cost  = TBD
```

### Reason for TBD
The current runtime does not provide:
1. exact token counts for the prompt, read SQL inputs, and generated output,
2. exact model name used for execution,
3. authoritative pricing for that model.

Once those values are available from the execution environment, the formula above can be applied directly.

---

## 14. Input Evidence Reviewed
- `Input/SOURCE_TILE_METADATA.sql`
- `Input/branch_operational_details.sql`
- `Input/SourceDDL.sql`
- `Input/confluence_content.txt`
- JIRA Ticket: `TCU-1` (`https://mmanasa.atlassian.net/browse/TCU-1`)

---

## 15. Final Recommendation
Proceed with an additive deployment using nullable column introduction, ETL enrichment, validation, and downstream contract review. Apply duplicate-key protection for tile metadata before production cutover. Use full reload deployment for branch reporting as specified, with reconciliation evidence captured after release.
