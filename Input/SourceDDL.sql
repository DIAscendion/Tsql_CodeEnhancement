CREATE TABLE IF NOT EXISTS analytics_db.SOURCE_HOME_TILE_EVENTS 
(
    event_id        STRING           COMMENT 'Unique event identifier',
    user_id         STRING           COMMENT 'User identifier',
    session_id      STRING           COMMENT 'Session identifier',
    event_ts        TIMESTAMP        COMMENT 'Timestamp of event',
    tile_id         STRING           COMMENT 'Tile identifier on homepage',
    event_type      STRING           COMMENT 'TILE_VIEW or TILE_CLICK',
    device_type     STRING           COMMENT 'Mobile, Web etc',
    app_version     STRING           COMMENT 'App version'
)
USING DELTA
PARTITIONED BY (date(event_ts))
COMMENT 'Raw events for homepage tile impressions and clicks';


CREATE TABLE IF NOT EXISTS analytics_db.SOURCE_INTERSTITIAL_EVENTS 
(
    event_id                         STRING    COMMENT 'Unique event identifier',
    user_id                          STRING    COMMENT 'User identifier',
    session_id                       STRING    COMMENT 'Session identifier',
    event_ts                         TIMESTAMP COMMENT 'Timestamp',
    tile_id                          STRING    COMMENT 'Tile that shows interstitial',
    interstitial_view_flag           BOOLEAN   COMMENT 'Interstitial view flag',
    primary_button_click_flag        BOOLEAN   COMMENT 'Primary CTA clicked',
    secondary_button_click_flag      BOOLEAN   COMMENT 'Secondary CTA clicked'
)
USING DELTA
PARTITIONED BY (date(event_ts))
COMMENT 'Raw events for interstitial impressions and CTA button clicks';


