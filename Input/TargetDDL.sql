CREATE TABLE IF NOT EXISTS reporting_db.TARGET_HOME_TILE_DAILY_SUMMARY 
(
    date                                DATE       COMMENT 'Reporting date',
    tile_id                             STRING     COMMENT 'Tile identifier',
    unique_tile_views                   LONG       COMMENT 'Distinct users who viewed the tile',
    unique_tile_clicks                  LONG       COMMENT 'Distinct users who clicked the tile',
    unique_interstitial_views           LONG       COMMENT 'Distinct users who viewed interstitial',
    unique_interstitial_primary_clicks  LONG       COMMENT 'Distinct users who clicked primary button',
    unique_interstitial_secondary_clicks LONG      COMMENT 'Distinct users who clicked secondary button'
)
USING DELTA
PARTITIONED BY (date)
COMMENT 'Daily aggregated tile-level metrics for reporting';


CREATE TABLE IF NOT EXISTS reporting_db.TARGET_HOME_TILE_GLOBAL_KPIS
(
    date                      DATE   COMMENT 'Reporting date',
    total_tile_views          LONG   COMMENT 'Total unique tile views across tiles',
    total_tile_clicks         LONG   COMMENT 'Total unique tile clicks across tiles',
    total_interstitial_views  LONG   COMMENT 'Total interstitial views',
    total_primary_clicks      LONG   COMMENT 'Total primary button clicks',
    total_secondary_clicks    LONG   COMMENT 'Total secondary button clicks',
    overall_ctr               DOUBLE COMMENT 'Tile Clicks / Tile Views',
    overall_primary_ctr       DOUBLE COMMENT 'Primary Clicks / Interstitial Views',
    overall_secondary_ctr     DOUBLE COMMENT 'Secondary Clicks / Interstitial Views'
)
USING DELTA
PARTITIONED BY (date)
COMMENT 'Daily global KPIs rolled up for dashboard';

