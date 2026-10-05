=============================================
Author: Ascendion AAVA
Date:
Description: Technical specification for integrating new source tables and extending target reporting outputs with enrichment attributes.
=============================================

# Title: Technical Specification for SOURCE_TILE_METADATA and BRANCH_OPERATIONAL_DETAILS Enhancements

## Introduction

This document defines the technical specification for two related enhancement inputs identified from the provided JIRA story and Confluence context:

1. **Primary enhancement from JIRA TCU-1**
   - Add new source table `analytics_db.SOURCE_TILE_METADATA`
   - Enrich reporting outputs with `tile_category`
   - Preserve backward compatibility using default value `UNKNOWN` when metadata is missing

2. **Additional enhancement from Confluence context**
   - Integrate `BRANCH_OPERATIONAL_DETAILS` into `BRANCH_SUMMARY_REPORT`
   - Add branch operational context columns to reporting outputs
   - Support full reload deployment for branch summary reporting

Based on the supplied files, the available physical models are:
- New source DDL for homepage tile events and interstitial events in Databricks Delta
- New source DDL for tile metadata in Databricks Delta
- New source DDL for branch operational details in Oracle-style SQL
- Confluence business context for branch reporting enhancement

Because the existing target data model DDL was not explicitly supplied as a standalone file, this specification derives required target changes from the JIRA and Confluence requirements and identifies the target objects logically.

### Business Objective

The enhancement enables:
- Category-level reporting for homepage tiles
- Improved reporting drilldowns and grouping by business function
- Regulatory and audit reporting enrichment for branch summaries
- Maintainable schema evolution with minimal disruption to downstream consumers

### In-Scope Objects

**Source objects**
- `analytics_db.SOURCE_TILE_METADATA`
- `analytics_db.SOURCE_HOME_TILE_EVENTS`
- `analytics_db.SOURCE_INTERSTITIAL_EVENTS`
- `BRANCH_OPERATIONAL_DETAILS`

**Target/logical reporting objects**
- Tile summary reporting target table/view/procedure (logical name inferred from JIRA; exact object name to be confirmed in implementation)
- `BRANCH_SUMMARY_REPORT`

---

## Code Changes

### 1. Impact Assessment

The following T-SQL / SQL / ETL object categories are expected to require modification.

| Object Type | Impact | Required Change |
|---|---|---|
| Source table DDL | High | Register and deploy `SOURCE_TILE_METADATA` and confirm availability of `SOURCE_HOME_TILE_EVENTS` / `SOURCE_INTERSTITIAL_EVENTS` |
| Target table DDL | High | Add `tile_category` to tile reporting target; add `REGION`, `LAST_AUDIT_DATE` to `BRANCH_SUMMARY_REPORT` |
| ETL/ELT scripts | High | Add left joins to enrichment tables and defaulting logic |
| Views | Medium | Extend reporting or semantic layer views to expose new columns |
| Stored procedures / orchestration SQL | High | Update load logic, merge statements, insert-selects, schema validations |
| Unit test SQL / data quality checks | High | Add schema, null-default, count parity, and enrichment tests |
| SQL Agent jobs / scheduler configs | Medium | If SQL Server orchestrates execution, include new dependency order and full reload requirement for branch report |
| Data dictionary / lineage scripts | Medium | Update metadata definitions and dependencies |

### 2. Source Object Changes

#### 2.1 New Table: `analytics_db.SOURCE_TILE_METADATA`

Provided DDL:

```sql
CREATE TABLE IF NOT EXISTS analytics_db.SOURCE_TILE_METADATA 
(
    tile_id        STRING    COMMENT 'Tile identifier',
    tile_name      STRING    COMMENT 'User-friendly tile name',
    tile_category  STRING    COMMENT 'Business or functional category of tile',
    is_active      BOOLEAN   COMMENT 'Indicates if tile is currently active',
    updated_ts     TIMESTAMP COMMENT 'Last update timestamp'
)
USING DELTA
COMMENT 'Master metadata for homepage tiles, used for business categorization and reporting enrichment';
```

#### 2.2 Existing Source Events Used in Enrichment

```sql
CREATE TABLE IF NOT EXISTS analytics_db.SOURCE_HOME_TILE_EVENTS 
(
    event_id        STRING,
    user_id         STRING,
    session_id      STRING,
    event_ts        TIMESTAMP,
    tile_id         STRING,
    event_type      STRING,
    device_type     STRING,
    app_version     STRING
)
USING DELTA
PARTITIONED BY (date(event_ts));
```

```sql
CREATE TABLE IF NOT EXISTS analytics_db.SOURCE_INTERSTITIAL_EVENTS 
(
    event_id                         STRING,
    user_id                          STRING,
    session_id                       STRING,
    event_ts                         TIMESTAMP,
    tile_id                          STRING,
    interstitial_view_flag           BOOLEAN,
    primary_button_click_flag        BOOLEAN,
    secondary_button_click_flag      BOOLEAN
)
USING DELTA
PARTITIONED BY (date(event_ts));
```

#### 2.3 Additional Source Table from Confluence Context

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

### 3. ETL / ELT Logic Changes

### 3.1 Tile Reporting Pipeline Changes

#### Existing logical process
Current tile reporting aggregates metrics at `tile_id` level only.

#### Required change
Add enrichment by joining `SOURCE_TILE_METADATA` to the tile event summary flow so that `tile_category` is populated in the final reporting dataset.

#### Join rule
- Join type: `LEFT JOIN`
- Join key: `tile_id`
- Default behavior: if metadata is missing, populate `tile_category = 'UNKNOWN'`

#### Transformation logic
- `tile_category = COALESCE(m.tile_category, 'UNKNOWN')`
- Optional defensive handling for blanks:
  `COALESCE(NULLIF(TRIM(m.tile_category), ''), 'UNKNOWN')`

#### Pseudocode

```sql
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
        SUM(CASE WHEN interstitial_view_flag = TRUE THEN 1 ELSE 0 END) AS interstitial_views,
        SUM(CASE WHEN primary_button_click_flag = TRUE THEN 1 ELSE 0 END) AS primary_cta_clicks,
        SUM(CASE WHEN secondary_button_click_flag = TRUE THEN 1 ELSE 0 END) AS secondary_cta_clicks
    FROM analytics_db.SOURCE_INTERSTITIAL_EVENTS
    GROUP BY CAST(event_ts AS DATE), tile_id
),
final_summary AS (
    SELECT
        t.event_date,
        t.tile_id,
        COALESCE(NULLIF(TRIM(m.tile_category), ''), 'UNKNOWN') AS tile_category,
        t.tile_views,
        t.tile_clicks,
        COALESCE(i.interstitial_views, 0) AS interstitial_views,
        COALESCE(i.primary_cta_clicks, 0) AS primary_cta_clicks,
        COALESCE(i.secondary_cta_clicks, 0) AS secondary_cta_clicks,
        CASE
            WHEN t.tile_views = 0 THEN 0
            ELSE CAST(t.tile_clicks AS DECIMAL(18,4)) / CAST(t.tile_views AS DECIMAL(18,4))
        END AS ctr
    FROM tile_events t
    LEFT JOIN interstitial_events i
        ON t.event_date = i.event_date
       AND t.tile_id = i.tile_id
    LEFT JOIN analytics_db.SOURCE_TILE_METADATA m
        ON t.tile_id = m.tile_id
)
SELECT *
FROM final_summary;
```

### 3.2 Target Load Logic Changes for Tile Reporting

The load step that writes to the tile reporting target must be modified to:
- Include `tile_category` in `SELECT`
- Include `tile_category` in `INSERT`, `MERGE`, or overwrite schema
- Validate schema evolution in tests
- Preserve historical logic where no metadata exists

#### Example `INSERT ... SELECT`

```sql
INSERT INTO analytics_db.TARGET_TILE_DAILY_SUMMARY
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
SELECT
    event_date,
    tile_id,
    COALESCE(NULLIF(TRIM(tile_category), ''), 'UNKNOWN') AS tile_category,
    tile_views,
    tile_clicks,
    interstitial_views,
    primary_cta_clicks,
    secondary_cta_clicks,
    ctr
FROM vw_tile_daily_summary_stg;
```

#### Example `MERGE`

```sql
MERGE INTO analytics_db.TARGET_TILE_DAILY_SUMMARY AS tgt
USING analytics_db.STG_TILE_DAILY_SUMMARY AS src
    ON tgt.event_date = src.event_date
   AND tgt.tile_id = src.tile_id
WHEN MATCHED THEN UPDATE SET
    tgt.tile_category = COALESCE(NULLIF(TRIM(src.tile_category), ''), 'UNKNOWN'),
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
        COALESCE(NULLIF(TRIM(src.tile_category), ''), 'UNKNOWN'),
        src.tile_views,
        src.tile_clicks,
        src.interstitial_views,
        src.primary_cta_clicks,
        src.secondary_cta_clicks,
        src.ctr
    );
```

### 3.3 Branch Reporting Pipeline Changes

Based on Confluence, `BRANCH_OPERATIONAL_DETAILS` must be integrated into `BRANCH_SUMMARY_REPORT`.

#### Required change
- Join source branch fact/base dataset to `BRANCH_OPERATIONAL_DETAILS` on `BRANCH_ID`
- Add `REGION` and `LAST_AUDIT_DATE` to final target
- Perform full reload of `BRANCH_SUMMARY_REPORT`
- Optionally use `IS_ACTIVE = 'Y'` filter if business confirms only active branches should enrich report

#### Pseudocode

```sql
SELECT
    b.BRANCH_ID,
    b.BRANCH_NAME,
    b.REPORT_DATE,
    COALESCE(o.REGION, 'UNKNOWN') AS REGION,
    o.LAST_AUDIT_DATE,
    b.TOTAL_ACCOUNTS,
    b.TOTAL_BALANCE
FROM BRANCH_BASE_SUMMARY b
LEFT JOIN BRANCH_OPERATIONAL_DETAILS o
    ON b.BRANCH_ID = o.BRANCH_ID;
```

#### Full reload pattern

```sql
TRUNCATE TABLE analytics_db.BRANCH_SUMMARY_REPORT;

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
    b.REPORT_DATE,
    COALESCE(o.REGION, 'UNKNOWN') AS REGION,
    o.LAST_AUDIT_DATE,
    b.TOTAL_ACCOUNTS,
    b.TOTAL_BALANCE
FROM analytics_db.BRANCH_BASE_SUMMARY b
LEFT JOIN oracle_src.BRANCH_OPERATIONAL_DETAILS o
    ON b.BRANCH_ID = o.BRANCH_ID;
```

### 4. Specific Objects to Modify

Because exact existing object names were not supplied, the following object list is defined by logical role and should be mapped to physical names during implementation.

#### 4.1 Tile enhancement objects
- Source DDL deployment script for `analytics_db.SOURCE_TILE_METADATA`
- Daily tile summary ETL notebook/script/stored procedure
- Tile summary staging view
- Tile summary target table DDL
- Tile summary semantic/reporting view
- Schema validation and unit test scripts
- Data dictionary / metadata registration script

#### 4.2 Branch enhancement objects
- Oracle source ingestion or extraction script for `BRANCH_OPERATIONAL_DETAILS`
- `BRANCH_SUMMARY_REPORT` target DDL
- Branch summary full reload script
- Branch reporting semantic view(s)
- Regression and reconciliation scripts

### 5. Validation and Test Changes

#### Tile metadata tests
- Verify `tile_category` column exists in target schema
- Verify populated value when metadata exists
- Verify `UNKNOWN` when no row exists in metadata
- Verify blank `tile_category` defaults to `UNKNOWN`
- Verify record counts unchanged relative to pre-enrichment aggregation
- Verify no duplicate rows introduced by metadata join

#### Example validation SQL

```sql
SELECT COUNT(*) AS unmatched_tile_categories
FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
WHERE tile_category IS NULL;
```

Expected result: `0`

```sql
SELECT tile_id, COUNT(*) AS cnt
FROM analytics_db.SOURCE_TILE_METADATA
GROUP BY tile_id
HAVING COUNT(*) > 1;
```

Expected result: `0` or resolved through latest-record logic.

#### Branch tests
- Verify `REGION` and `LAST_AUDIT_DATE` columns exist in `BRANCH_SUMMARY_REPORT`
- Verify full reload completes successfully
- Verify branch row counts align with base summary population rules
- Verify branch-to-operational-detail join does not duplicate branch summary rows
- Verify date type conversion for `LAST_AUDIT_DATE` is correct

---

## Data Model Updates

### 1. Source Data Model Updates

#### 1.1 New Source Entity: `SOURCE_TILE_METADATA`

| Column | Data Type | Nullable | Key | Description |
|---|---|---:|---|---|
| tile_id | STRING | Yes* | Business key | Tile identifier |
| tile_name | STRING | Yes |  | Friendly tile name |
| tile_category | STRING | Yes |  | Functional/business category |
| is_active | BOOLEAN | Yes |  | Active indicator |
| updated_ts | TIMESTAMP | Yes |  | Last metadata refresh timestamp |

**Recommended constraints / quality rules**
- Enforce uniqueness on `tile_id` where platform supports it logically
- Maintain latest active record per `tile_id`
- Add not-null expectation for `tile_id` in ingestion validation
- Optional index/Z-ORDER optimization on `tile_id` in Databricks

#### 1.2 Existing Source Event Entities

`SOURCE_HOME_TILE_EVENTS`
- Grain: one row per homepage tile event
- Join key to metadata: `tile_id`
- Partition: `date(event_ts)`

`SOURCE_INTERSTITIAL_EVENTS`
- Grain: one row per interstitial event
- Join key to metadata: `tile_id`
- Partition: `date(event_ts)`

#### 1.3 Additional Source Entity: `BRANCH_OPERATIONAL_DETAILS`

| Column | Data Type | Nullable | Key | Description |
|---|---|---:|---|---|
| BRANCH_ID | INT | No | Primary Key | Branch identifier |
| REGION | VARCHAR2(50) | Yes |  | Branch region |
| MANAGER_NAME | VARCHAR2(100) | Yes |  | Branch manager |
| LAST_AUDIT_DATE | DATE | Yes |  | Most recent audit date |
| IS_ACTIVE | CHAR(1) | Yes |  | Active flag |

### 2. Target Data Model Updates

#### 2.1 Tile Reporting Target

The JIRA explicitly requires addition of:
- `tile_category STRING COMMENT 'Functional category of the tile'`

#### Recommended target table shape

| Column | Data Type | Nullable | Description |
|---|---|---:|---|
| event_date | DATE | No | Summary date |
| tile_id | STRING | No | Tile identifier |
| tile_category | STRING | No | Functional category of tile; default `UNKNOWN` |
| tile_views | BIGINT | No | Count of tile view events |
| tile_clicks | BIGINT | No | Count of tile click events |
| interstitial_views | BIGINT | No | Count of interstitial impressions |
| primary_cta_clicks | BIGINT | No | Count of primary CTA clicks |
| secondary_cta_clicks | BIGINT | No | Count of secondary CTA clicks |
| ctr | DECIMAL(18,4) | No | Click-through rate |

#### DDL change example

```sql
ALTER TABLE analytics_db.TARGET_TILE_DAILY_SUMMARY
ADD COLUMNS (
    tile_category STRING COMMENT 'Functional category of the tile'
);
```

If a table recreation approach is used:

```sql
CREATE TABLE IF NOT EXISTS analytics_db.TARGET_TILE_DAILY_SUMMARY
(
    event_date             DATE,
    tile_id                STRING,
    tile_category          STRING COMMENT 'Functional category of the tile',
    tile_views             BIGINT,
    tile_clicks            BIGINT,
    interstitial_views     BIGINT,
    primary_cta_clicks     BIGINT,
    secondary_cta_clicks   BIGINT,
    ctr                    DECIMAL(18,4)
)
USING DELTA;
```

#### Recommended constraints / optimization
- Logical primary key: `(event_date, tile_id)`
- If category history is type-1 only, no additional key required
- Consider clustering/Z-ORDER by `(event_date, tile_id)`

### 2.2 Branch Summary Target

Confluence requires adding:
- `REGION`
- `LAST_AUDIT_DATE`

#### Recommended target additions

| Column | Data Type | Nullable | Description |
|---|---|---:|---|
| REGION | STRING / VARCHAR(50) | Yes/No by policy | Branch region; default `UNKNOWN` if absent |
| LAST_AUDIT_DATE | DATE | Yes | Last operational audit date |

#### DDL change example

```sql
ALTER TABLE analytics_db.BRANCH_SUMMARY_REPORT
ADD COLUMNS (
    REGION STRING,
    LAST_AUDIT_DATE DATE
);
```

### 3. Data Model Relationship Diagram

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
| BRANCH_SUMMARY_REPORT                            |
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

## Source-to-Target Mapping

### 1. Tile Reporting Mapping

| Source Table | Source Column | Target Table | Target Column | Transformation Rule (T-SQL/SQL) | Notes |
|---|---|---|---|---|---|
| `SOURCE_HOME_TILE_EVENTS` | `event_ts` | `TARGET_TILE_DAILY_SUMMARY` | `event_date` | `CAST(event_ts AS DATE)` | Daily aggregation grain |
| `SOURCE_HOME_TILE_EVENTS` | `tile_id` | `TARGET_TILE_DAILY_SUMMARY` | `tile_id` | `tile_id` | Join key and reporting key |
| `SOURCE_TILE_METADATA` | `tile_category` | `TARGET_TILE_DAILY_SUMMARY` | `tile_category` | `COALESCE(NULLIF(TRIM(m.tile_category), ''), 'UNKNOWN')` | Default if metadata missing or blank |
| `SOURCE_HOME_TILE_EVENTS` | `event_id` | `TARGET_TILE_DAILY_SUMMARY` | `tile_views` | `SUM(CASE WHEN event_type = 'TILE_VIEW' THEN 1 ELSE 0 END)` | Aggregated metric |
| `SOURCE_HOME_TILE_EVENTS` | `event_id` | `TARGET_TILE_DAILY_SUMMARY` | `tile_clicks` | `SUM(CASE WHEN event_type = 'TILE_CLICK' THEN 1 ELSE 0 END)` | Aggregated metric |
| `SOURCE_INTERSTITIAL_EVENTS` | `interstitial_view_flag` | `TARGET_TILE_DAILY_SUMMARY` | `interstitial_views` | `SUM(CASE WHEN interstitial_view_flag = TRUE THEN 1 ELSE 0 END)` | Aggregated metric |
| `SOURCE_INTERSTITIAL_EVENTS` | `primary_button_click_flag` | `TARGET_TILE_DAILY_SUMMARY` | `primary_cta_clicks` | `SUM(CASE WHEN primary_button_click_flag = TRUE THEN 1 ELSE 0 END)` | Aggregated metric |
| `SOURCE_INTERSTITIAL_EVENTS` | `secondary_button_click_flag` | `TARGET_TILE_DAILY_SUMMARY` | `secondary_cta_clicks` | `SUM(CASE WHEN secondary_button_click_flag = TRUE THEN 1 ELSE 0 END)` | Aggregated metric |
| Derived | `tile_clicks`, `tile_views` | `TARGET_TILE_DAILY_SUMMARY` | `ctr` | `CASE WHEN tile_views = 0 THEN 0 ELSE CAST(tile_clicks AS DECIMAL(18,4)) / CAST(tile_views AS DECIMAL(18,4)) END` | Avoid divide-by-zero |

### 2. Branch Reporting Mapping

| Source Table | Source Column | Target Table | Target Column | Transformation Rule (T-SQL/SQL) | Notes |
|---|---|---|---|---|---|
| `BRANCH_BASE_SUMMARY` | `BRANCH_ID` | `BRANCH_SUMMARY_REPORT` | `BRANCH_ID` | `b.BRANCH_ID` | Primary branch key |
| `BRANCH_BASE_SUMMARY` | `BRANCH_NAME` | `BRANCH_SUMMARY_REPORT` | `BRANCH_NAME` | `b.BRANCH_NAME` | Existing mapping retained |
| `BRANCH_BASE_SUMMARY` | `REPORT_DATE` | `BRANCH_SUMMARY_REPORT` | `REPORT_DATE` | `CAST(b.REPORT_DATE AS DATE)` | Normalize to reporting date |
| `BRANCH_OPERATIONAL_DETAILS` | `REGION` | `BRANCH_SUMMARY_REPORT` | `REGION` | `COALESCE(NULLIF(TRIM(o.REGION), ''), 'UNKNOWN')` | Default if missing |
| `BRANCH_OPERATIONAL_DETAILS` | `LAST_AUDIT_DATE` | `BRANCH_SUMMARY_REPORT` | `LAST_AUDIT_DATE` | `CAST(o.LAST_AUDIT_DATE AS DATE)` | Preserve date semantics |
| `BRANCH_BASE_SUMMARY` | `TOTAL_ACCOUNTS` | `BRANCH_SUMMARY_REPORT` | `TOTAL_ACCOUNTS` | `b.TOTAL_ACCOUNTS` | Existing mapping retained |
| `BRANCH_BASE_SUMMARY` | `TOTAL_BALANCE` | `BRANCH_SUMMARY_REPORT` | `TOTAL_BALANCE` | `b.TOTAL_BALANCE` | Existing mapping retained |

### 3. Transformation and Business Rules Summary

#### Tile enhancement rules
- Join metadata by `tile_id`
- Use `LEFT JOIN` to preserve all existing tile summary records
- Default `tile_category` to `UNKNOWN` when metadata record is absent or blank
- Do not change existing event count aggregation logic
- Prevent duplicate results by ensuring one metadata row per `tile_id`

#### Branch enhancement rules
- Join operational details by `BRANCH_ID`
- Prefer full reload of `BRANCH_SUMMARY_REPORT` as specified in Confluence
- Default missing `REGION` to `UNKNOWN`
- Preserve `LAST_AUDIT_DATE` as `DATE`
- Confirm whether inactive branches (`IS_ACTIVE <> 'Y'`) should be excluded or only used as informational enrichment

---

## Assumptions and Constraints

### Assumptions
- The physical target tile summary object exists but its exact DDL/name was not provided; this specification uses `analytics_db.TARGET_TILE_DAILY_SUMMARY` as a logical placeholder.
- `SOURCE_TILE_METADATA` contains at most one active record per `tile_id`; if not, latest-record logic must be added using `updated_ts`.
- Existing ETL frameworks support schema evolution for new nullable columns.
- Databricks Delta is the execution/storage layer for tile-related data.
- `BRANCH_OPERATIONAL_DETAILS` originates from Oracle and is available to the target pipeline through an ingestion layer.
- Existing measures in target reporting tables must remain unchanged apart from new enrichment columns.

### Constraints
- Backward compatibility is mandatory.
- Existing record counts and KPI totals must not change due to enrichment joins.
- New columns must comply with enterprise naming and data governance standards.
- Security and access controls for source metadata tables must match current reporting pipeline standards.
- For branch reporting, deployment requires full reload of `BRANCH_SUMMARY_REPORT`.
- Historical backfill for tile category is out of scope unless separately requested.
- Dashboard changes are downstream and not part of this implementation.

### Risks
- Duplicate `tile_id` values in `SOURCE_TILE_METADATA` could multiply target rows.
- Oracle-to-Databricks type conversion may require explicit casting for `DATE` and character fields.
- Blank category/region values may appear as valid strings unless normalized.
- Schema drift may break automated tests if target contracts are not updated simultaneously.

### Mitigation
- Add duplicate key validation on `SOURCE_TILE_METADATA.tile_id`
- Apply explicit `CAST`, `COALESCE`, `NULLIF`, and `TRIM`
- Update unit and regression test baselines before deployment
- Execute full reconciliation after release

---

## References

1. **JIRA Ticket**: `TCU-1`
   - Summary: `Tsql Code Update`
   - URL: `https://mmanasa.atlassian.net/browse/TCU-1`

2. **Input Files Reviewed**
   - `Input/SOURCE_TILE_METADATA.sql`
   - `Input/SourceDDL.sql`
   - `Input/branch_operational_details.sql`
   - `Input/confluence_content.txt`

3. **Key Source Objects**
   - `analytics_db.SOURCE_TILE_METADATA`
   - `analytics_db.SOURCE_HOME_TILE_EVENTS`
   - `analytics_db.SOURCE_INTERSTITIAL_EVENTS`
   - `BRANCH_OPERATIONAL_DETAILS`

4. **Target / Logical Objects**
   - `analytics_db.TARGET_TILE_DAILY_SUMMARY` *(logical placeholder, confirm physical object name)*
   - `analytics_db.BRANCH_SUMMARY_REPORT`

---

## Cost Estimation and Justification

Pricing data for the active model is not exposed in the available tool/system context, so exact token-based run cost cannot be calculated reliably from system pricing metadata.

### Available status
- Model used: Not programmatically exposed in tool responses
- Input token count: Not programmatically exposed
- Output token count: Not programmatically exposed
- Model pricing: Not programmatically exposed

### Formula to apply when pricing becomes available

```text
Input Cost  = input_tokens  * input_cost_per_token
Output Cost = output_tokens * output_cost_per_token
Total Cost  = Input Cost + Output Cost
```

### Required data to finalize actual cost
- Exact model name
- Input token count
- Output token count
- Price per input token for that model
- Price per output token for that model

Because these values are unavailable in the runtime context, the actual numeric cost is marked as **TBD**.
