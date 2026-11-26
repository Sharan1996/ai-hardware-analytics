with quarters as (
        select cik, ticker, tag, unit, period_start, period_end, period_type,
           datediff('day',
                    coalesce(lag(period_end) over (partition by cik, tag, unit, period_start order by period_end),
                             dateadd('day', -1, period_start)),
                    period_end)                                                as days_covered,
           value - coalesce(lag(value) over (partition by cik, tag, unit, period_start order by period_end), 0)
                                                                               as quarter_value
    from ai_hw.staging.stg_sec_facts
    where period_type <> 'instant'
    qualify days_covered between 80 and 100
),

one_per_quarter as (
    select *
    from quarters
    qualify row_number() over (
        partition by cik, tag, unit, period_end
        order by case when period_type = 'quarter' then 0 else 1 end
    ) = 1
),
tag_map as (
    select * from (values
        ('RevenueFromContractWithCustomerExcludingAssessedTax', 'revenue',          1),
        ('Revenues',                                            'revenue',          2),
        ('SalesRevenueNet',                                     'revenue',          3),
        ('CostOfGoodsAndServicesSold',                          'cost_of_revenue',  1),
        ('CostOfRevenue',                                       'cost_of_revenue',  2),
        ('GrossProfit',                                         'gross_profit',     1),
        ('OperatingIncomeLoss',                                 'operating_income', 1),
        ('NetIncomeLoss',                                       'net_income',       1),
        ('ResearchAndDevelopmentExpense',                       'rnd_expense',      1),
        ('PaymentsToAcquirePropertyPlantAndEquipment',          'capex',            1)
    ) as t (tag, metric, priority)
),
metric_quarters as (
    select q.cik, q.ticker, m.metric, q.period_end, q.quarter_value
    from one_per_quarter q
    join tag_map m on q.tag = m.tag
    qualify row_number() over (
        partition by q.cik, m.metric, q.period_end
        order by m.priority
    ) = 1
),
inventory as (
    select cik, ticker,
           'inventory'  as metric,
           period_end,
           value        as quarter_value
    from ai_hw.staging.stg_sec_facts
    where tag = 'InventoryNet'
      and period_type = 'instant'
),
all_metrics as (
    select cik, ticker, metric, period_end, quarter_value from metric_quarters
    union all
    select cik, ticker, metric, period_end, quarter_value from inventory
),
fiscal_years as (
    select cik, period_end as fy_end, year(period_end) as fiscal_year
    from ai_hw.staging.stg_sec_facts
    where period_type = 'year'
      and tag in ('RevenueFromContractWithCustomerExcludingAssessedTax', 'Revenues', 'SalesRevenueNet')
    qualify row_number() over (partition by cik, period_end order by tag) = 1
),

fiscal_years_plus_current as (
    select cik, fy_end, fiscal_year from fiscal_years
    union all
    select cik,
           dateadd('day', 371, max(fy_end)) as fy_end,
           max(fiscal_year) + 1             as fiscal_year
    from fiscal_years
    group by cik
),

fiscal_calendar as (
    select cik, fiscal_year, fy_end,
    coalesce(lag(fy_end) over (partition by cik order by fy_end),
    dateadd('day', -371, fy_end))                  as prev_fy_end
           
    from fiscal_years_plus_current
),
labeled as (
    select a.*,
           f.fiscal_year,
           round(datediff('day', f.prev_fy_end, a.period_end) / 91.3) as fiscal_quarter
    from all_metrics a
    join fiscal_calendar f
      on a.cik = f.cik
     and a.period_end >  f.prev_fy_end
     and a.period_end <= f.fy_end
),

pivoted as (
    select cik, ticker, fiscal_year, fiscal_quarter,
           max(case when metric = 'revenue'          then period_end    end) as period_end,
           max(case when metric = 'revenue'          then quarter_value end) as revenue,
           max(case when metric = 'cost_of_revenue'  then quarter_value end) as cost_of_revenue,
           max(case when metric = 'gross_profit'     then quarter_value end) as gross_profit,
           max(case when metric = 'operating_income' then quarter_value end) as operating_income,
           max(case when metric = 'net_income'       then quarter_value end) as net_income,
           max(case when metric = 'rnd_expense'      then quarter_value end) as rnd_expense,
           max(case when metric = 'capex'            then quarter_value end) as capex,
           max(case when metric = 'inventory'        then quarter_value end) as inventory
    from labeled
    group by cik, ticker, fiscal_year, fiscal_quarter
)

select
    cik || '-' || fiscal_year || '-Q' || fiscal_quarter          as company_quarter_id,
    cik, ticker, fiscal_year, fiscal_quarter, period_end,
    date_trunc('quarter', dateadd('day', -45, period_end))::date  as calendar_quarter,
    revenue, cost_of_revenue,
    coalesce(gross_profit, revenue - cost_of_revenue)             as gross_profit,
    operating_income, net_income, rnd_expense, capex, inventory
from pivoted
where revenue is not null