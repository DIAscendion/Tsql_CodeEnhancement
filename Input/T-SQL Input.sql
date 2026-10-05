/*
===============================================================================
                    CHANGE MANAGEMENT / REVISION HISTORY
===============================================================================
File Name       : home_tile_reporting_etl.sql
Author          : <Your Name>
Created Date    : 2025-12-02
Last Modified   : <Auto-updated>
Version         : 1.0.0
Release         : R1 – Home Tile Reporting Enhancement

Functional Description:
    This ETL pipeline performs the following:
    - Reads home tile interaction events and interstitial events from source tables
    - Computes aggregated metrics:
        • Unique Tile Views
        • Unique Tile Clicks
        • Unique Interstitial Views
        • Unique Primary Button Clicks
        • Unique Secondary Button Clicks
        • CTRs for homepage tiles and interstitial buttons
    - Loads aggregated results into:
        • TARGET_HOME_TILE_DAILY_SUMMARY
        • TARGET_HOME_TILE_GLOBAL_KPIS
    - Supports idempotent daily partition replacement
    - Designed for scalable SQL Server / Azure SQL workloads

Change Log:
-------------------------------------------------------------------------------
Version     Date          Author          Description
-------------------------------------------------------------------------------
1.0.0       2025-12-02    <Your Name>     Initial version of the ETL pipeline
-------------------------------------------------------------------------------
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

DECLARE @PROCESS_DATE DATE = '2025-12-01';

DECLARE @PIPELINE_NAME VARCHAR(100) = 'HOME_TILE_REPORTING_ETL';

-- =============================================================================
-- TEMP TABLE CLEANUP
-- =============================================================================

IF OBJECT_ID('tempdb..#TILE_AGG') IS NOT NULL
    DROP TABLE #TILE_AGG;

IF OBJECT_ID('tempdb..#INTER_AGG') IS NOT NULL
    DROP TABLE #INTER_AGG;

IF OBJECT_ID('tempdb..#DAILY_SUMMARY') IS NOT NULL
    DROP TABLE #DAILY_SUMMARY;

IF OBJECT_ID('tempdb..#GLOBAL_KPIS') IS NOT NULL
    DROP TABLE #GLOBAL_KPIS;


-- =============================================================================
-- READ AND AGGREGATE HOME TILE EVENTS
-- =============================================================================

SELECT
    tile_id,

    COUNT(DISTINCT
        CASE
            WHEN event_type = 'TILE_VIEW'
            THEN user_id
        END
    ) AS unique_tile_views,

    COUNT(DISTINCT
        CASE
            WHEN event_type = 'TILE_CLICK'
            THEN user_id
        END
    ) AS unique_tile_clicks

INTO #TILE_AGG

FROM analytics_db.SOURCE_HOME_TILE_EVENTS

WHERE event_ts >= @PROCESS_DATE
  AND event_ts < DATEADD(DAY, 1, @PROCESS_DATE)

GROUP BY
    tile_id;


-- =============================================================================
-- READ AND AGGREGATE INTERSTITIAL EVENTS
-- =============================================================================

SELECT
    tile_id,

    COUNT(DISTINCT
        CASE
            WHEN interstitial_view_flag = 1
            THEN user_id
        END
    ) AS unique_interstitial_views,

    COUNT(DISTINCT
        CASE
            WHEN primary_button_click_flag = 1
            THEN user_id
        END
    ) AS unique_interstitial_primary_clicks,

    COUNT(DISTINCT
        CASE
            WHEN secondary_button_click_flag = 1
            THEN user_id
        END
    ) AS unique_interstitial_secondary_clicks

INTO #INTER_AGG

FROM analytics_db.SOURCE_INTERSTITIAL_EVENTS

WHERE event_ts >= @PROCESS_DATE
  AND event_ts < DATEADD(DAY, 1, @PROCESS_DATE)

GROUP BY
    tile_id;


-- =============================================================================
-- DAILY TILE + INTERSTITIAL SUMMARY
-- =============================================================================

SELECT
    @PROCESS_DATE AS [date],
    COALESCE(T.tile_id, I.tile_id) AS tile_id,

    COALESCE(T.unique_tile_views, 0) AS unique_tile_views,
    COALESCE(T.unique_tile_clicks, 0) AS unique_tile_clicks,

    COALESCE(I.unique_interstitial_views, 0)
        AS unique_interstitial_views,

    COALESCE(I.unique_interstitial_primary_clicks, 0)
        AS unique_interstitial_primary_clicks,

    COALESCE(I.unique_interstitial_secondary_clicks, 0)
        AS unique_interstitial_secondary_clicks

INTO #DAILY_SUMMARY

FROM #TILE_AGG T

FULL OUTER JOIN #INTER_AGG I
    ON T.tile_id = I.tile_id;


-- =============================================================================
-- GLOBAL KPIs
-- =============================================================================

SELECT
    [date],

    SUM(unique_tile_views) AS total_tile_views,

    SUM(unique_tile_clicks) AS total_tile_clicks,

    SUM(unique_interstitial_views) AS total_interstitial_views,

    SUM(unique_interstitial_primary_clicks) AS total_primary_clicks,

    SUM(unique_interstitial_secondary_clicks) AS total_secondary_clicks,

    CASE
        WHEN SUM(unique_tile_views) > 0
        THEN
            CAST(SUM(unique_tile_clicks) AS DECIMAL(18,6))
            / SUM(unique_tile_views)
        ELSE 0.0
    END AS overall_ctr,

    CASE
        WHEN SUM(unique_interstitial_views) > 0
        THEN
            CAST(SUM(unique_interstitial_primary_clicks) AS DECIMAL(18,6))
            / SUM(unique_interstitial_views)
        ELSE 0.0
    END AS overall_primary_ctr,

    CASE
        WHEN SUM(unique_interstitial_views) > 0
        THEN
            CAST(SUM(unique_interstitial_secondary_clicks) AS DECIMAL(18,6))
            / SUM(unique_interstitial_views)
        ELSE 0.0
    END AS overall_secondary_ctr

INTO #GLOBAL_KPIS

FROM #DAILY_SUMMARY

GROUP BY
    [date];


-- =============================================================================
-- WRITE TARGET TABLES – IDEMPOTENT DAILY REPLACEMENT
-- =============================================================================

BEGIN TRY

    BEGIN TRANSACTION;


    -- -------------------------------------------------------------------------
    -- Remove existing data for processing date
    -- -------------------------------------------------------------------------

    DELETE FROM reporting_db.TARGET_HOME_TILE_DAILY_SUMMARY
    WHERE [date] = @PROCESS_DATE;


    DELETE FROM reporting_db.TARGET_HOME_TILE_GLOBAL_KPIS
    WHERE [date] = @PROCESS_DATE;


    -- -------------------------------------------------------------------------
    -- Insert daily summary
    -- -------------------------------------------------------------------------

    INSERT INTO reporting_db.TARGET_HOME_TILE_DAILY_SUMMARY
    (
        [date],
        tile_id,
        unique_tile_views,
        unique_tile_clicks,
        unique_interstitial_views,
        unique_interstitial_primary_clicks,
        unique_interstitial_secondary_clicks
    )
    SELECT
        [date],
        tile_id,
        unique_tile_views,
        unique_tile_clicks,
        unique_interstitial_views,
        unique_interstitial_primary_clicks,
        unique_interstitial_secondary_clicks
    FROM #DAILY_SUMMARY;


    -- -------------------------------------------------------------------------
    -- Insert global KPIs
    -- -------------------------------------------------------------------------

    INSERT INTO reporting_db.TARGET_HOME_TILE_GLOBAL_KPIS
    (
        [date],
        total_tile_views,
        total_tile_clicks,
        total_interstitial_views,
        total_primary_clicks,
        total_secondary_clicks,
        overall_ctr,
        overall_primary_ctr,
        overall_secondary_ctr
    )
    SELECT
        [date],
        total_tile_views,
        total_tile_clicks,
        total_interstitial_views,
        total_primary_clicks,
        total_secondary_clicks,
        overall_ctr,
        overall_primary_ctr,
        overall_secondary_ctr
    FROM #GLOBAL_KPIS;


    COMMIT TRANSACTION;


    PRINT 'ETL completed successfully for '
          + CONVERT(VARCHAR(10), @PROCESS_DATE, 120);


END TRY

BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT 'ETL failed for '
          + CONVERT(VARCHAR(10), @PROCESS_DATE, 120);

    THROW;

END CATCH;


-- =============================================================================
-- TEMP TABLE CLEANUP
-- =============================================================================

DROP TABLE IF EXISTS #TILE_AGG;
DROP TABLE IF EXISTS #INTER_AGG;
DROP TABLE IF EXISTS #DAILY_SUMMARY;
DROP TABLE IF EXISTS #GLOBAL_KPIS;

SET NOCOUNT OFF;
