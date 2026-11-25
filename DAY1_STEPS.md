# Day 1 steps

Run everything from `D:\AI Hardware analytics\ai-hardware-analytics` in the VS Code terminal.

## 1. Snowflake (15 min)
1. Sign up at signup.snowflake.com (Standard edition, any US region).
2. Open a Snowsight worksheet, paste `setup/snowflake_setup.sql`, and run all.
3. Note your account identifier (bottom-left menu > your account > copy account identifier).

## 2. Python environment (10 min)
```
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## 3. Secrets (5 min)
- Copy `.env.example` to `.env` and fill it in.
- Copy `dbt\profiles.yml.example` to `dbt\profiles.yml` and fill it in.
- Run `git status`: neither `.env` nor `profiles.yml` should be listed. If they are, fix `.gitignore` before committing.

## 4. Pull SEC data (10 min)
```
python ingestion\pull_sec.py --local
```
Check `data\raw\sec_facts.csv` looks right (one row per value), then load to Snowflake:
```
python ingestion\pull_sec.py
```

## 5. dbt (30 min)
```
cd dbt
dbt debug --profiles-dir .
dbt seed --profiles-dir .
dbt build --profiles-dir .
```
`dbt build` runs `stg_sec_facts` and its tests. In Snowsight, check:
```sql
select ticker, tag, period_type, count(*)
from ai_hw.staging.stg_sec_facts
group by 1, 2, 3
order by 1, 2, 3;
```

## 6. Push
```
cd ..
git add .
git commit -m "Day 1: SEC ingestion + stg_sec_facts"
git push
```
