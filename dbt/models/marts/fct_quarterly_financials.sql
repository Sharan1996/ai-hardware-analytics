with quarters as (

    select * from {{ ref('int_quarterly_financials') }}

),

with_prior_year as (

    select *,
           lag(revenue)     over (partition by cik, fiscal_quarter order by fiscal_year) as revenue_prior_year,
           lag(fiscal_year) over (partition by cik, fiscal_quarter order by fiscal_year) as prior_fiscal_year
    from quarters

)

select
    company_quarter_id,
    cik,
    fiscal_year,
    fiscal_quarter,
    'FY' || fiscal_year || ' Q' || fiscal_quarter                        as fiscal_quarter_label,
    period_end,
    calendar_quarter,

    -- reported amounts (USD)
    revenue,
    cost_of_revenue,
    gross_profit,
    operating_income,
    net_income,
    rnd_expense,
    capex,
    inventory,

    -- KPIs
    gross_profit     / nullif(revenue, 0)                                as gross_margin_pct,
    operating_income / nullif(revenue, 0)                                as operating_margin_pct,
    rnd_expense      / nullif(revenue, 0)                                as rnd_intensity_pct,
    capex            / nullif(revenue, 0)                                as capex_intensity_pct,
    inventory        / nullif(cost_of_revenue / 91, 0)                   as inventory_days,
    case when prior_fiscal_year = fiscal_year - 1
         then revenue / nullif(revenue_prior_year, 0) - 1
    end                                                                  as revenue_yoy_pct

from with_prior_year