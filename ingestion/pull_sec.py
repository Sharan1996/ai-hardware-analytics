"""
Pull XBRL "company facts" from SEC EDGAR for each company in dbt/seeds/companies.csv,
flatten them to one row per reported value, and load to Snowflake RAW.SEC_FACTS.

Run from the repo root:
    python ingestion/pull_sec.py            # pull + load to Snowflake
    python ingestion/pull_sec.py --local    # pull + save CSV only (no Snowflake)

Needs a .env file in the repo root (see .env.example). Never commit .env.
"""

import argparse
import csv
import os
import sys
import time
from pathlib import Path

import pandas as pd
import requests
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[1]
COMPANIES_CSV = REPO_ROOT / "dbt" / "seeds" / "companies.csv"
LOCAL_OUT = REPO_ROOT / "data" / "raw" / "sec_facts.csv"
SEC_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik}.json"

# Only keep the tags the marts use. Add more here when you need them.
TAGS = {
    "Revenues",
    "RevenueFromContractWithCustomerExcludingAssessedTax",
    "CostOfRevenue",
    "CostOfGoodsAndServicesSold",
    "GrossProfit",
    "OperatingIncomeLoss",
    "NetIncomeLoss",
    "ResearchAndDevelopmentExpense",
    "PaymentsToAcquirePropertyPlantAndEquipment",
    "InventoryNet",
}


def load_companies() -> list[dict]:
    with open(COMPANIES_CSV, newline="") as f:
        return [row for row in csv.DictReader(f) if row["cik"].strip()]


def fetch_company_facts(cik: str, user_agent: str) -> dict:
    url = SEC_URL.format(cik=cik.zfill(10))
    resp = requests.get(url, headers={"User-Agent": user_agent}, timeout=60)
    resp.raise_for_status()
    return resp.json()


def flatten(payload: dict, ticker: str) -> list[dict]:
    """One row per (taxonomy, tag, unit, period, filing)."""
    rows = []
    for taxonomy, tags in payload.get("facts", {}).items():
        for tag, body in tags.items():
            if tag not in TAGS:
                continue
            for unit, values in body.get("units", {}).items():
                for v in values:
                    rows.append(
                        {
                            "CIK": str(payload.get("cik")).zfill(10),
                            "TICKER": ticker,
                            "ENTITY_NAME": payload.get("entityName"),
                            "TAXONOMY": taxonomy,
                            "TAG": tag,
                            "UNIT": unit,
                            "PERIOD_START": v.get("start"),  # empty for point-in-time values like inventory
                            "PERIOD_END": v.get("end"),
                            "VALUE": v.get("val"),
                            "FISCAL_YEAR": v.get("fy"),
                            "FISCAL_PERIOD": v.get("fp"),
                            "FORM": v.get("form"),
                            "FILED": v.get("filed"),
                            "ACCESSION": v.get("accn"),
                            "FRAME": v.get("frame"),
                        }
                    )
    return rows


def load_to_snowflake(df: pd.DataFrame) -> None:
    import snowflake.connector
    from snowflake.connector.pandas_tools import write_pandas

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role=os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "AIHA_WH"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "AI_HW"),
        schema="RAW",
    )
    try:
        df = df.copy()
        df["LOADED_AT"] = pd.Timestamp.utcnow().strftime("%Y-%m-%d %H:%M:%S")
        ok, _, nrows, _ = write_pandas(
            conn,
            df,
            table_name="SEC_FACTS",
            auto_create_table=True,
            overwrite=True,  # full refresh each run; SEC history is small
            quote_identifiers=False,
        )
        print(f"Snowflake load ok={ok}, rows={nrows}")
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local", action="store_true", help="save CSV only, skip Snowflake")
    args = parser.parse_args()

    load_dotenv(REPO_ROOT / ".env")
    user_agent = os.environ.get("SEC_USER_AGENT")
    if not user_agent:
        sys.exit("Set SEC_USER_AGENT in .env, e.g. 'Sharan Subramanian your.email@example.com'")

    all_rows = []
    for c in load_companies():
        print(f"Pulling {c['ticker']} (CIK {c['cik']})...")
        try:
            payload = fetch_company_facts(c["cik"], user_agent)
        except requests.HTTPError as e:
            print(f"  skipped: {e}")
            continue
        rows = flatten(payload, c["ticker"])
        print(f"  {len(rows):,} rows")
        all_rows.extend(rows)
        time.sleep(0.5)  # SEC asks for no more than 10 requests per second

    if not all_rows:
        sys.exit("No data pulled. Check CIKs and your internet connection.")

    df = pd.DataFrame(all_rows)
    LOCAL_OUT.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(LOCAL_OUT, index=False)
    print(f"Saved {len(df):,} rows to {LOCAL_OUT}")

    if not args.local:
        load_to_snowflake(df)


if __name__ == "__main__":
    main()
