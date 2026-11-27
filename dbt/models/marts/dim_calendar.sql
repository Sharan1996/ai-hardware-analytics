with quarters as (

    select dateadd('quarter',
                   row_number() over (order by seq4()) - 1,
                   '2008-01-01'::date)                       as calendar_quarter
    from table(generator(rowcount => 80))

)

select
    calendar_quarter,
    last_day(dateadd('month', 2, calendar_quarter))          as quarter_end_date,
    year(calendar_quarter)                                   as calendar_year,
    quarter(calendar_quarter)                                as quarter_number,
    'Q' || quarter(calendar_quarter) || ' ' || year(calendar_quarter)   as quarter_label,
    year(calendar_quarter) * 10 + quarter(calendar_quarter)  as quarter_sort_key
from quarters