-- Run once in a Snowsight worksheet after creating your trial account.
use role accountadmin;

create warehouse if not exists aiha_wh
  warehouse_size = 'XSMALL'
  auto_suspend = 60          -- seconds idle before it stops billing
  auto_resume = true
  initially_suspended = true;

create database if not exists ai_hw;
create schema if not exists ai_hw.raw;      -- loaded by ingestion/
create schema if not exists ai_hw.staging;  -- dbt stg_ models
create schema if not exists ai_hw.marts;    -- dbt fct_ / dim_ models

-- Safety net: stop the warehouse if it burns more than 20 credits a month.
create or replace resource monitor aiha_monitor
  with credit_quota = 20
  frequency = monthly
  start_timestamp = immediately
  triggers on 80 percent do notify
           on 100 percent do suspend;

alter warehouse aiha_wh set resource_monitor = aiha_monitor;
