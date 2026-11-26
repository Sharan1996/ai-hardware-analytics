-- Fails if the 4 quarters of a fiscal year don't add up to the annual revenue the company reported.
{{ config(severity = 'warn') }}
with annual as (

    select cik,
           year(period_end) as fiscal_year,
           value            as annual_revenue
    from {{ ref('stg_sec_facts') }}
    where period_type = 'year'
      and tag in ('RevenueFromContractWithCustomerExcludingAssessedTax', 'Revenues', 'SalesRevenueNet')
    qualify row_number() over (
        partition by cik, period_end
        order by case tag
                     when 'RevenueFromContractWithCustomerExcludingAssessedTax' then 1
                     when 'Revenues' then 2
                     else 3
                 end
    ) = 1

),

quarters as (

    select cik, fiscal_year,
           count(*)     as quarters_found,
           sum(revenue) as sum_of_quarters
    from {{ ref('int_quarterly_financials') }}
    group by cik, fiscal_year

)

select a.cik, a.fiscal_year,
       a.annual_revenue, q.sum_of_quarters,
       q.sum_of_quarters - a.annual_revenue as difference
from annual a
join quarters q
  on a.cik = q.cik and a.fiscal_year = q.fiscal_year
where q.quarters_found = 4
  and abs(q.sum_of_quarters - a.annual_revenue) > 1000000