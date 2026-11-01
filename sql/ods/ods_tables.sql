-- ODS 层：原样保存原始数据，不做任何清洗

-- 网约车行程原始表
CREATE TABLE IF NOT EXISTS tlc.ods_hvfhv_trip (
    hvfhs_license_num     STRING,
    dispatching_base_num  STRING,
    originating_base_num  STRING,
    request_datetime      TIMESTAMP_NTZ,
    on_scene_datetime     TIMESTAMP_NTZ,
    pickup_datetime       TIMESTAMP_NTZ,
    dropoff_datetime      TIMESTAMP_NTZ,
    PULocationID          INT,
    DOLocationID          INT,
    trip_miles            DOUBLE,
    trip_time             BIGINT,
    base_passenger_fare   DOUBLE,
    tolls                 DOUBLE,
    bcf                   DOUBLE,
    sales_tax             DOUBLE,
    congestion_surcharge  DOUBLE,
    airport_fee           DOUBLE,
    tips                  DOUBLE,
    driver_pay            DOUBLE,
    shared_request_flag   STRING,
    shared_match_flag     STRING,
    access_a_ride_flag    STRING,
    wav_request_flag      STRING,
    wav_match_flag        STRING,
    cbd_congestion_fee    DOUBLE,
    month                 STRING
)
USING PARQUET
PARTITIONED BY (month)
LOCATION '/user/hive/warehouse/tlc.db/ods_hvfhv_trip'
COMMENT 'ODS: NYC TLC 网约车行程原始数据，按文件月份分区';

-- 登记已上传的两个月份分区
ALTER TABLE tlc.ods_hvfhv_trip ADD IF NOT EXISTS PARTITION (month = '2024-12');
ALTER TABLE tlc.ods_hvfhv_trip ADD IF NOT EXISTS PARTITION (month = '2025-01');

-- 区域对照表原始数据
CREATE TABLE IF NOT EXISTS tlc.ods_taxi_zone (
    LocationID    INT,
    Borough       STRING,
    Zone          STRING,
    service_zone  STRING
)
USING CSV
OPTIONS (header 'true')
LOCATION '/user/hive/warehouse/tlc.db/ods_taxi_zone'
COMMENT 'ODS: TLC 区域对照表原始数据';

