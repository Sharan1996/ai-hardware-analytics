-- One row per company, tag, unit and period: the latest filed value wins,
-- so restated numbers in later filings replace the original ones.

with source as (

    select * from {{ source('raw', 'sec_facts') }}

),

typed as (

    select
        lpad(cik::varchar, 10, '0')           as cik,
        ticker,
        entity_name,
        taxonomy,
        tag,
        unit,
        try_to_date(period_start)              as period_start,
        try_to_date(period_end)                as period_end,
        value::number(38, 4)                   as value,
        fiscal_year::int                       as fiscal_year,
        fiscal_period,
        form,
        try_to_date(filed)                     as filed_date,
        accession,
        frame
    from source
    where form in ('10-Q', '10-K', '10-Q/A', '10-K/A')

),

deduped as (

    select *
    from typed
    qualify row_number() over (
        partition by cik, taxonomy, tag, unit, period_start, period_end
        order by filed_date desc, accession desc
    ) = 1

)

select
    md5(concat_ws('|', cik, taxonomy, tag, unit,
        coalesce(period_start::varchar, ''), period_end::varchar))   as fact_id,
    *,
    datediff('day', period_start, period_end)                      as duration_days,
    case
        when period_start is null                          then 'instant'   -- balance-sheet value, e.g. inventory
        when datediff('day', period_start, period_end) between 80 and 100 then 'quarter'
        when datediff('day', period_start, period_end) between 350 and 380 then 'year'
        else 'other'                                                         -- e.g. 6- or 9-month year-to-date
    end                                                            as period_type
from deduped
