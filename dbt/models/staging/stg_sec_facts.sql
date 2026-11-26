with source as (

    select * from {{ source('raw', 'sec_facts') }}

),

cleaned as (

    select
        cik,
        ticker,
        tag,
        unit,
        try_to_date(period_start)      as period_start,
        try_to_date(period_end)        as period_end,
        value::number(38, 2)           as value,
        form,
        try_to_date(filed)             as filed
    from source
    where form in ('10-Q', '10-K', '10-Q/A', '10-K/A')
    qualify row_number() over (
        partition by cik, tag, unit, period_start, period_end
        order by filed desc
    ) = 1

)

select
    cik || '|' || tag || '|' || unit || '|'
        || coalesce(period_start::varchar, '') || '|' || period_end::varchar   as fact_id,
    *,
    case
        when period_start is null then 'instant'
        when datediff('day', period_start, period_end) between 80 and 100 then 'quarter'
        when datediff('day', period_start, period_end) between 350 and 380 then 'year'
        else 'other'
    end as period_type
from cleaned