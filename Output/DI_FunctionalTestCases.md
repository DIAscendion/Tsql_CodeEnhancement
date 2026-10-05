=============================================
Author: Ascendion AAVA
Date: 
Description: Functional test cases for validating tile metadata enrichment and branch operational detail integration based on Jira TCU-1 and related Confluence specifications.
=============================================

# Functional Test Cases

## Requirement Coverage Summary
- Jira Ticket: `TCU-1`
- Source objects covered:
  - `analytics_db.SOURCE_TILE_METADATA`
  - `analytics_db.SOURCE_HOME_TILE_EVENTS`
  - `analytics_db.SOURCE_INTERSTITIAL_EVENTS`
  - `BRANCH_OPERATIONAL_DETAILS`
- Target/logical objects covered:
  - `analytics_db.TARGET_TILE_DAILY_SUMMARY`
  - `analytics_db.BRANCH_SUMMARY_REPORT`
- Functional areas covered:
  - Source object availability
  - Target schema evolution
  - ETL join behavior
  - Defaulting and null/blank handling
  - Aggregation preservation
  - Duplicate prevention
  - Full reload logic for branch summary
  - Data type and result validation

---

### Test Case ID: TC_TCU-1_01
**Title:** Validate SOURCE_TILE_METADATA source table is created and accessible
**Description:** Verify that the new source table `analytics_db.SOURCE_TILE_METADATA` exists in the database/catalog and is available for ETL consumption as required by Jira.
**Preconditions:**
- Database/catalog connection is available.
- Deployment of source DDL has been completed.
**Steps to Execute:**
1. Connect to the SQL environment.
2. Execute the metadata lookup query:
   ```sql
   SELECT table_schema, table_name
   FROM information_schema.tables
   WHERE table_schema = 'analytics_db'
     AND table_name = 'SOURCE_TILE_METADATA';
   ```
3. Execute a sample read query:
   ```sql
   SELECT *
   FROM analytics_db.SOURCE_TILE_METADATA;
   ```
**Expected Result:**
- The table `analytics_db.SOURCE_TILE_METADATA` exists.
- The table is queryable without object-not-found errors.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_02
**Title:** Validate SOURCE_TILE_METADATA schema contains required columns
**Description:** Verify that the source metadata table contains the required columns defined in the technical specification.
**Preconditions:**
- `analytics_db.SOURCE_TILE_METADATA` exists.
**Steps to Execute:**
1. Execute the schema validation query:
   ```sql
   SELECT column_name, data_type
   FROM information_schema.columns
   WHERE table_schema = 'analytics_db'
     AND table_name = 'SOURCE_TILE_METADATA'
   ORDER BY ordinal_position;
   ```
2. Compare returned columns with expected list: `tile_id`, `tile_name`, `tile_category`, `is_active`, `updated_ts`.
**Expected Result:**
- All required columns are present in the source table.
- Column names align with the specification.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_03
**Title:** Validate target tile summary schema includes tile_category column
**Description:** Ensure the tile reporting target table has been extended with the new `tile_category` column.
**Preconditions:**
- Target table `analytics_db.TARGET_TILE_DAILY_SUMMARY` exists.
- Deployment for schema change is completed.
**Steps to Execute:**
1. Execute the column existence query:
   ```sql
   SELECT column_name, data_type
   FROM information_schema.columns
   WHERE table_schema = 'analytics_db'
     AND table_name = 'TARGET_TILE_DAILY_SUMMARY'
     AND column_name = 'tile_category';
   ```
**Expected Result:**
- A single row is returned for `tile_category`.
- The data type is string/varchar-compatible per implementation.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_04
**Title:** Validate BRANCH_SUMMARY_REPORT schema includes REGION and LAST_AUDIT_DATE
**Description:** Ensure branch summary reporting target schema has been extended with branch operational enrichment columns from Confluence requirements.
**Preconditions:**
- `analytics_db.BRANCH_SUMMARY_REPORT` exists.
- Branch schema deployment is completed.
**Steps to Execute:**
1. Execute the schema query:
   ```sql
   SELECT column_name, data_type
   FROM information_schema.columns
   WHERE table_name = 'BRANCH_SUMMARY_REPORT'
     AND column_name IN ('REGION', 'LAST_AUDIT_DATE')
   ORDER BY column_name;
   ```
**Expected Result:**
- Both `REGION` and `LAST_AUDIT_DATE` are present in `BRANCH_SUMMARY_REPORT`.
- `LAST_AUDIT_DATE` is a date-compatible type.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_05
**Title:** Validate tile_category is enriched when matching metadata exists
**Description:** Verify that the ETL correctly joins tile event data with metadata and populates `tile_category` when a matching `tile_id` exists.
**Preconditions:**
- Test data exists in `SOURCE_HOME_TILE_EVENTS` for a known `tile_id`.
- Matching record exists in `SOURCE_TILE_METADATA` with populated `tile_category`.
- ETL load to `TARGET_TILE_DAILY_SUMMARY` has been executed.
**Steps to Execute:**
1. Insert or identify a test tile ID present in both source events and metadata.
2. Run the ETL/load process for tile summary.
3. Execute verification query:
   ```sql
   SELECT tgt.event_date,
          tgt.tile_id,
          tgt.tile_category,
          src.tile_category AS source_tile_category
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY tgt
   INNER JOIN analytics_db.SOURCE_TILE_METADATA src
       ON tgt.tile_id = src.tile_id
   WHERE tgt.tile_id = '<TEST_TILE_ID>';
   ```
**Expected Result:**
- `TARGET_TILE_DAILY_SUMMARY.tile_category` matches `SOURCE_TILE_METADATA.tile_category` for the test tile.
- No null or incorrect fallback value is used when metadata exists and is populated.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_06
**Title:** Validate tile_category defaults to UNKNOWN when metadata record is missing
**Description:** Verify backward compatibility rule that `tile_category` defaults to `UNKNOWN` when there is no corresponding metadata row for a tile event.
**Preconditions:**
- A tile event exists in `SOURCE_HOME_TILE_EVENTS` for a `tile_id` with no matching record in `SOURCE_TILE_METADATA`.
- ETL load has been executed.
**Steps to Execute:**
1. Identify or insert a `tile_id` in `SOURCE_HOME_TILE_EVENTS` that does not exist in `SOURCE_TILE_METADATA`.
2. Execute the tile summary ETL process.
3. Run the verification query:
   ```sql
   SELECT event_date, tile_id, tile_category
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   WHERE tile_id = '<UNMAPPED_TILE_ID>';
   ```
**Expected Result:**
- The target row is created/preserved.
- `tile_category` is populated as `UNKNOWN`.
- No rows are lost due to the missing metadata mapping.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_07
**Title:** Validate blank tile_category in metadata is normalized to UNKNOWN
**Description:** Ensure blank or whitespace-only metadata category values are transformed to `UNKNOWN` using the specified null/blank handling logic.
**Preconditions:**
- A metadata record exists for a `tile_id` with `tile_category` set to blank or whitespace.
- Matching tile event exists.
- ETL load has been executed.
**Steps to Execute:**
1. Insert or identify metadata row where `tile_category` is `''` or whitespace for a known `tile_id`.
2. Execute the tile summary ETL process.
3. Run the verification query:
   ```sql
   SELECT tgt.tile_id,
          tgt.tile_category,
          src.tile_category AS raw_source_category
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY tgt
   INNER JOIN analytics_db.SOURCE_TILE_METADATA src
       ON tgt.tile_id = src.tile_id
   WHERE tgt.tile_id = '<BLANK_CATEGORY_TILE_ID>';
   ```
**Expected Result:**
- `tgt.tile_category` is `UNKNOWN`.
- Blank source category values do not propagate to the target.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_08
**Title:** Validate target tile_category is never NULL after load
**Description:** Confirm that the ETL defaulting logic prevents null values in the target `tile_category` column.
**Preconditions:**
- Tile summary ETL load has completed.
**Steps to Execute:**
1. Run the null-check query:
   ```sql
   SELECT COUNT(*) AS null_tile_category_count
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   WHERE tile_category IS NULL;
   ```
**Expected Result:**
- `null_tile_category_count` = 0.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_09
**Title:** Validate tile reporting row counts remain unchanged after metadata enrichment
**Description:** Verify that the left join enrichment does not alter the number of aggregated tile summary records compared to the base pre-enrichment aggregation.
**Preconditions:**
- Tile event source data exists.
- ETL load has completed.
**Steps to Execute:**
1. Compute expected aggregated base count:
   ```sql
   WITH tile_events AS (
       SELECT CAST(event_ts AS DATE) AS event_date,
              tile_id
       FROM analytics_db.SOURCE_HOME_TILE_EVENTS
       GROUP BY CAST(event_ts AS DATE), tile_id
   )
   SELECT COUNT(*) AS expected_count
   FROM tile_events;
   ```
2. Compute target count:
   ```sql
   SELECT COUNT(*) AS target_count
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY;
   ```
3. Compare both counts.
**Expected Result:**
- `target_count` equals `expected_count` for the test scope/load window.
- Enrichment join does not create additional or missing aggregated rows.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_10
**Title:** Validate metadata join does not introduce duplicate tile summary rows
**Description:** Ensure the metadata join preserves the logical target grain of one row per `event_date` and `tile_id`.
**Preconditions:**
- Tile summary ETL load has completed.
**Steps to Execute:**
1. Run the duplicate detection query:
   ```sql
   SELECT event_date,
          tile_id,
          COUNT(*) AS row_count
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   GROUP BY event_date, tile_id
   HAVING COUNT(*) > 1;
   ```
**Expected Result:**
- No rows are returned.
- Target grain remains unique per `event_date`, `tile_id`.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_11
**Title:** Validate SOURCE_TILE_METADATA has no duplicate tile_id values
**Description:** Verify source metadata quality by ensuring `tile_id` values are unique or that duplicates are identified for remediation before they can multiply reporting rows.
**Preconditions:**
- `SOURCE_TILE_METADATA` contains test/active data.
**Steps to Execute:**
1. Execute the duplicate key check:
   ```sql
   SELECT tile_id,
          COUNT(*) AS cnt
   FROM analytics_db.SOURCE_TILE_METADATA
   GROUP BY tile_id
   HAVING COUNT(*) > 1;
   ```
**Expected Result:**
- No rows are returned, or duplicates are flagged as a data defect requiring latest-record resolution.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_12
**Title:** Validate tile view and click aggregations remain correct after enhancement
**Description:** Ensure that existing reporting measures are unchanged by the addition of metadata enrichment.
**Preconditions:**
- Source event data is available for a known test date and tile.
- Tile summary ETL has been executed.
**Steps to Execute:**
1. Compute expected aggregations from source:
   ```sql
   SELECT CAST(event_ts AS DATE) AS event_date,
          tile_id,
          SUM(CASE WHEN event_type = 'TILE_VIEW' THEN 1 ELSE 0 END) AS expected_tile_views,
          SUM(CASE WHEN event_type = 'TILE_CLICK' THEN 1 ELSE 0 END) AS expected_tile_clicks
   FROM analytics_db.SOURCE_HOME_TILE_EVENTS
   WHERE tile_id = '<TEST_TILE_ID>'
   GROUP BY CAST(event_ts AS DATE), tile_id;
   ```
2. Query target values:
   ```sql
   SELECT event_date,
          tile_id,
          tile_views,
          tile_clicks
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   WHERE tile_id = '<TEST_TILE_ID>';
   ```
3. Compare source-derived values with target values.
**Expected Result:**
- `tile_views` and `tile_clicks` in target match source-derived aggregation exactly.
- Metadata enrichment does not alter measure calculations.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_13
**Title:** Validate interstitial metrics are populated correctly in target summary
**Description:** Verify that interstitial metrics continue to load correctly alongside the new metadata enrichment.
**Preconditions:**
- Matching `tile_id` and date records exist in `SOURCE_INTERSTITIAL_EVENTS`.
- Tile summary ETL has been executed.
**Steps to Execute:**
1. Compute expected interstitial aggregations:
   ```sql
   SELECT CAST(event_ts AS DATE) AS event_date,
          tile_id,
          SUM(CASE WHEN interstitial_view_flag = TRUE THEN 1 ELSE 0 END) AS expected_interstitial_views,
          SUM(CASE WHEN primary_button_click_flag = TRUE THEN 1 ELSE 0 END) AS expected_primary_cta_clicks,
          SUM(CASE WHEN secondary_button_click_flag = TRUE THEN 1 ELSE 0 END) AS expected_secondary_cta_clicks
   FROM analytics_db.SOURCE_INTERSTITIAL_EVENTS
   WHERE tile_id = '<TEST_TILE_ID>'
   GROUP BY CAST(event_ts AS DATE), tile_id;
   ```
2. Query target summary for the same tile/date.
3. Compare values.
**Expected Result:**
- `interstitial_views`, `primary_cta_clicks`, and `secondary_cta_clicks` match expected source-derived values.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_14
**Title:** Validate CTR calculation is correct when tile_views is greater than zero
**Description:** Ensure click-through rate is calculated accurately for rows with non-zero tile views.
**Preconditions:**
- Tile summary ETL has been executed for data where `tile_views > 0`.
**Steps to Execute:**
1. Query target row:
   ```sql
   SELECT event_date,
          tile_id,
          tile_views,
          tile_clicks,
          ctr
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   WHERE tile_id = '<TEST_TILE_ID>'
     AND tile_views > 0;
   ```
2. Independently calculate expected CTR using:
   ```sql
   SELECT CAST(tile_clicks AS DECIMAL(18,4)) / CAST(tile_views AS DECIMAL(18,4)) AS expected_ctr
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   WHERE tile_id = '<TEST_TILE_ID>'
     AND tile_views > 0;
   ```
3. Compare expected and stored CTR.
**Expected Result:**
- `ctr` equals `tile_clicks / tile_views` with expected decimal precision.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_15
**Title:** Validate CTR defaults to zero when tile_views equals zero
**Description:** Ensure divide-by-zero protection works and CTR is set to 0 when no tile views exist for a target row.
**Preconditions:**
- Test data or scenario exists producing `tile_views = 0` in final summary logic.
**Steps to Execute:**
1. Execute or simulate ETL for a tile/date where `tile_views = 0` and clicks are absent.
2. Query the target row:
   ```sql
   SELECT event_date,
          tile_id,
          tile_views,
          tile_clicks,
          ctr
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY
   WHERE tile_views = 0;
   ```
**Expected Result:**
- `ctr` is `0`.
- No divide-by-zero error occurs during ETL execution.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_16
**Title:** Validate ETL pipeline can read SOURCE_TILE_METADATA successfully
**Description:** Verify the ETL process completes successfully with the new metadata source dependency included.
**Preconditions:**
- ETL job/stored procedure/notebook is deployed with metadata join logic.
- Source tables are accessible.
**Steps to Execute:**
1. Execute the tile summary ETL job/stored procedure.
2. Capture execution status and any SQL error output.
3. Query target table for rows loaded in the current execution window.
**Expected Result:**
- ETL completes successfully without source object or schema reference errors.
- Output rows are written to the target table.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_17
**Title:** Validate branch summary full reload completes successfully
**Description:** Ensure the branch reporting pipeline performs the required full reload of `BRANCH_SUMMARY_REPORT` without execution failure.
**Preconditions:**
- `BRANCH_BASE_SUMMARY` and `BRANCH_OPERATIONAL_DETAILS` are available.
- Branch reload script is deployed.
**Steps to Execute:**
1. Execute the branch full reload process.
2. Confirm truncate and insert operations complete.
3. Query the target table:
   ```sql
   SELECT COUNT(*) AS branch_summary_count
   FROM analytics_db.BRANCH_SUMMARY_REPORT;
   ```
**Expected Result:**
- Full reload completes successfully.
- `BRANCH_SUMMARY_REPORT` is repopulated with expected data.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_18
**Title:** Validate REGION is populated from BRANCH_OPERATIONAL_DETAILS when match exists
**Description:** Verify branch summary enrichment correctly maps `REGION` from branch operational details.
**Preconditions:**
- Matching `BRANCH_ID` exists in `BRANCH_BASE_SUMMARY` and `BRANCH_OPERATIONAL_DETAILS`.
- Branch reload has been executed.
**Steps to Execute:**
1. Query branch target and source for a known branch:
   ```sql
   SELECT tgt.BRANCH_ID,
          tgt.REGION,
          src.REGION AS source_region
   FROM analytics_db.BRANCH_SUMMARY_REPORT tgt
   INNER JOIN BRANCH_OPERATIONAL_DETAILS src
       ON tgt.BRANCH_ID = src.BRANCH_ID
   WHERE tgt.BRANCH_ID = <TEST_BRANCH_ID>;
   ```
**Expected Result:**
- `BRANCH_SUMMARY_REPORT.REGION` matches `BRANCH_OPERATIONAL_DETAILS.REGION` for the branch when source region is populated.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_19
**Title:** Validate LAST_AUDIT_DATE is populated correctly in branch summary
**Description:** Verify that `LAST_AUDIT_DATE` is correctly transferred to the target and preserved as a date value.
**Preconditions:**
- Matching branch operational details record exists with populated `LAST_AUDIT_DATE`.
- Branch reload completed.
**Steps to Execute:**
1. Execute verification query:
   ```sql
   SELECT tgt.BRANCH_ID,
          tgt.LAST_AUDIT_DATE,
          src.LAST_AUDIT_DATE AS source_last_audit_date
   FROM analytics_db.BRANCH_SUMMARY_REPORT tgt
   INNER JOIN BRANCH_OPERATIONAL_DETAILS src
       ON tgt.BRANCH_ID = src.BRANCH_ID
   WHERE tgt.BRANCH_ID = <TEST_BRANCH_ID>;
   ```
**Expected Result:**
- Target `LAST_AUDIT_DATE` matches source value.
- Value is stored/returned as a date-compatible type with no invalid conversion.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_20
**Title:** Validate REGION defaults to UNKNOWN when branch operational details are missing
**Description:** Ensure the left join logic preserves branch summary rows and defaults `REGION` to `UNKNOWN` when no operational details record exists.
**Preconditions:**
- A branch exists in `BRANCH_BASE_SUMMARY` with no matching `BRANCH_OPERATIONAL_DETAILS` row.
- Branch full reload has been executed.
**Steps to Execute:**
1. Identify a branch ID present only in `BRANCH_BASE_SUMMARY`.
2. Query target row:
   ```sql
   SELECT BRANCH_ID,
          REGION,
          LAST_AUDIT_DATE
   FROM analytics_db.BRANCH_SUMMARY_REPORT
   WHERE BRANCH_ID = <UNMAPPED_BRANCH_ID>;
   ```
**Expected Result:**
- The branch row exists in the target.
- `REGION` = `UNKNOWN`.
- `LAST_AUDIT_DATE` is NULL when no operational detail exists unless alternate business rule is implemented.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_21
**Title:** Validate blank REGION values are normalized to UNKNOWN
**Description:** Ensure blank or whitespace `REGION` values from branch operational details do not propagate to reporting output.
**Preconditions:**
- `BRANCH_OPERATIONAL_DETAILS` contains a branch with blank/whitespace `REGION`.
- Matching branch exists in base summary.
- Full reload completed.
**Steps to Execute:**
1. Query the branch target row for the test branch:
   ```sql
   SELECT tgt.BRANCH_ID,
          tgt.REGION,
          src.REGION AS raw_source_region
   FROM analytics_db.BRANCH_SUMMARY_REPORT tgt
   INNER JOIN BRANCH_OPERATIONAL_DETAILS src
       ON tgt.BRANCH_ID = src.BRANCH_ID
   WHERE tgt.BRANCH_ID = <BLANK_REGION_BRANCH_ID>;
   ```
**Expected Result:**
- `tgt.REGION` is `UNKNOWN`.
- Blank source region values are normalized during load.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_22
**Title:** Validate branch summary row counts align with base summary after enrichment
**Description:** Verify that enrichment from `BRANCH_OPERATIONAL_DETAILS` does not change the number of branch summary rows loaded from the base source.
**Preconditions:**
- Branch reload has completed.
**Steps to Execute:**
1. Query expected count from base summary:
   ```sql
   SELECT COUNT(*) AS expected_base_count
   FROM analytics_db.BRANCH_BASE_SUMMARY;
   ```
2. Query target row count:
   ```sql
   SELECT COUNT(*) AS target_count
   FROM analytics_db.BRANCH_SUMMARY_REPORT;
   ```
3. Compare counts.
**Expected Result:**
- `target_count` equals `expected_base_count` for the load scope.
- No extra or missing rows are introduced by enrichment.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_23
**Title:** Validate branch operational join does not create duplicate rows in BRANCH_SUMMARY_REPORT
**Description:** Ensure the join to `BRANCH_OPERATIONAL_DETAILS` preserves expected branch report grain and does not multiply rows.
**Preconditions:**
- Branch reload has completed.
**Steps to Execute:**
1. Run duplicate detection query:
   ```sql
   SELECT BRANCH_ID,
          REPORT_DATE,
          COUNT(*) AS row_count
   FROM analytics_db.BRANCH_SUMMARY_REPORT
   GROUP BY BRANCH_ID, REPORT_DATE
   HAVING COUNT(*) > 1;
   ```
**Expected Result:**
- No rows are returned.
- Target contains only one row per branch/report date grain.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_24
**Title:** Validate BRANCH_OPERATIONAL_DETAILS primary key uniqueness on BRANCH_ID
**Description:** Verify source branch operational details do not contain duplicate `BRANCH_ID` values that could cause duplicate branch summary rows.
**Preconditions:**
- `BRANCH_OPERATIONAL_DETAILS` is populated.
**Steps to Execute:**
1. Execute duplicate key query:
   ```sql
   SELECT BRANCH_ID,
          COUNT(*) AS cnt
   FROM BRANCH_OPERATIONAL_DETAILS
   GROUP BY BRANCH_ID
   HAVING COUNT(*) > 1;
   ```
**Expected Result:**
- No rows are returned.
- Source key uniqueness supports safe one-to-one enrichment.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_25
**Title:** Validate branch summary preserves existing measures after enrichment
**Description:** Ensure existing branch summary metrics such as `TOTAL_ACCOUNTS` and `TOTAL_BALANCE` remain unchanged after adding operational enrichment columns.
**Preconditions:**
- Base and target branch data are available after full reload.
**Steps to Execute:**
1. Query source base summary values:
   ```sql
   SELECT BRANCH_ID,
          REPORT_DATE,
          TOTAL_ACCOUNTS,
          TOTAL_BALANCE
   FROM analytics_db.BRANCH_BASE_SUMMARY
   WHERE BRANCH_ID = <TEST_BRANCH_ID>;
   ```
2. Query corresponding target values:
   ```sql
   SELECT BRANCH_ID,
          REPORT_DATE,
          TOTAL_ACCOUNTS,
          TOTAL_BALANCE
   FROM analytics_db.BRANCH_SUMMARY_REPORT
   WHERE BRANCH_ID = <TEST_BRANCH_ID>;
   ```
3. Compare measure values.
**Expected Result:**
- `TOTAL_ACCOUNTS` and `TOTAL_BALANCE` in target match the base summary values exactly.
- Enrichment does not modify existing branch measures.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_26
**Title:** Validate no schema drift errors occur during tile target load
**Description:** Ensure the target write logic successfully handles the newly added `tile_category` column without schema mismatch or missing column failures.
**Preconditions:**
- Updated ETL/load logic is deployed.
- Target schema includes `tile_category`.
**Steps to Execute:**
1. Execute the tile load process.
2. Review job logs or SQL execution output.
3. Confirm target table contains newly loaded rows with `tile_category` populated.
**Expected Result:**
- Load completes successfully with no schema drift or column mismatch errors.
- `tile_category` is included in inserted/updated rows.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_27
**Title:** Validate historical compatibility for existing rows after tile schema change
**Description:** Confirm that previously existing target rows remain queryable and that introducing `tile_category` does not break existing reporting output shape beyond the additive column.
**Preconditions:**
- Target table contains rows created before enhancement or representative backfilled rows.
**Steps to Execute:**
1. Query existing target rows:
   ```sql
   SELECT TOP 100 event_date,
                  tile_id,
                  tile_views,
                  tile_clicks,
                  tile_category
   FROM analytics_db.TARGET_TILE_DAILY_SUMMARY;
   ```
2. Validate that legacy measure columns still return expected values.
3. Validate that `tile_category` is populated with either source-enriched value or `UNKNOWN`.
**Expected Result:**
- Existing rows remain accessible.
- Prior columns behave unchanged.
- New column does not break backward compatibility for consumers tolerant of additive schema.
**Linked Jira Ticket:** TCU-1

### Test Case ID: TC_TCU-1_28
**Title:** Validate branch report supports NULL LAST_AUDIT_DATE when source value is absent
**Description:** Ensure the target handles missing audit dates correctly and does not fail load when `LAST_AUDIT_DATE` is null in source.
**Preconditions:**
- A `BRANCH_OPERATIONAL_DETAILS` record exists with `LAST_AUDIT_DATE` = NULL.
- Matching branch exists in base summary.
- Full reload completed.
**Steps to Execute:**
1. Query target row for the branch:
   ```sql
   SELECT tgt.BRANCH_ID,
          tgt.LAST_AUDIT_DATE
   FROM analytics_db.BRANCH_SUMMARY_REPORT tgt
   WHERE tgt.BRANCH_ID = <NULL_AUDIT_BRANCH_ID>;
   ```
2. Compare with source branch operational detail.
**Expected Result:**
- Load completes successfully.
- `LAST_AUDIT_DATE` is NULL in target for that branch.
- No data type conversion or load failure occurs.
**Linked Jira Ticket:** TCU-1

---

## Traceability Matrix

| Requirement / Acceptance Criterion | Covered By Test Cases |
|---|---|
| SOURCE_TILE_METADATA table is created in analytics_db | TC_TCU-1_01, TC_TCU-1_02 |
| ETL pipeline reads metadata table successfully | TC_TCU-1_16 |
| tile_category is added to target table | TC_TCU-1_03 |
| tile_category appears accurately in reporting outputs | TC_TCU-1_05, TC_TCU-1_06, TC_TCU-1_07, TC_TCU-1_08 |
| Backward compatibility maintained with UNKNOWN default | TC_TCU-1_06, TC_TCU-1_07, TC_TCU-1_20, TC_TCU-1_21, TC_TCU-1_27 |
| Existing counts remain unchanged | TC_TCU-1_09, TC_TCU-1_22 |
| No duplicate rows introduced by enrichment joins | TC_TCU-1_10, TC_TCU-1_11, TC_TCU-1_23, TC_TCU-1_24 |
| Existing metric calculations remain correct | TC_TCU-1_12, TC_TCU-1_13, TC_TCU-1_14, TC_TCU-1_15, TC_TCU-1_25 |
| BRANCH_SUMMARY_REPORT includes REGION and LAST_AUDIT_DATE | TC_TCU-1_04 |
| Branch full reload works successfully | TC_TCU-1_17 |
| Branch enrichment populates REGION and LAST_AUDIT_DATE correctly | TC_TCU-1_18, TC_TCU-1_19, TC_TCU-1_20, TC_TCU-1_21, TC_TCU-1_28 |
| Pipeline runs with no schema drift | TC_TCU-1_26 |

---

## Cost Estimation and Justification

Actual token counts, model identity, and pricing are not exposed in the available runtime/tool context.
Therefore, an exact numeric execution cost cannot be computed reliably from system-provided metadata.

### Available Status
- **Model used:** Not programmatically exposed
- **Total input tokens:** Not programmatically exposed
- **Total output tokens:** Not programmatically exposed
- **Input token price:** Not programmatically exposed
- **Output token price:** Not programmatically exposed

### Formula
```text
Input Cost  = input_tokens * input_cost_per_token
Output Cost = output_tokens * output_cost_per_token
Total Cost  = Input Cost + Output Cost
```

### Current Result
```text
Input Cost  = TBD
Output Cost = TBD
Total Cost  = TBD
```

### Reason for TBD
The environment does not provide:
1. exact token counts for the prompt, Jira content, and GitHub input files,
2. the exact model name used for this run,
3. authoritative per-token pricing for the active model.

**GitHub output file created:** `Output/DI_FunctionalTestCases.md`
**Repository path:** `DIAscendion/Tsql_CodeEnhancement`
