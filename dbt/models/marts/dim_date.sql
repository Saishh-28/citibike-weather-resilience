-- dim_date
-- One row per New York calendar date in the analysis window (726 rows).
-- Power BI needs a dedicated date table ("Mark as date table") for date hierarchies
-- and period comparisons. It also carries the holiday flag (assumption A8): without it,
-- Thanksgiving or Christmas would look like an unexplained weather anomaly.
--
-- Holidays: US federal holidays from seeds/us_federal_holidays.csv, including the
-- "observed" weekday when the holiday falls on a weekend (e.g. Christmas 2016 on a Sunday
-- -> Monday 26 Dec off). NYC public schools and other local days are NOT included (limitation).

with days as (

    select
        dateadd(
            'day',
            row_number() over (order by seq4()) - 1,
            '{{ var("overlap_start") }}'::date
        )                                                       as date_day
    from table(generator(rowcount => 726))

),

holidays as (

    select holiday_date, holiday_name
    from {{ ref('us_federal_holidays') }}

)

select
    d.date_day,
    year(d.date_day)                                            as year,
    quarter(d.date_day)                                         as quarter,
    month(d.date_day)                                           as month,
    monthname(d.date_day)                                       as month_name,
    day(d.date_day)                                             as day_of_month,
    dayofweekiso(d.date_day)                                    as day_of_week,        -- 1 = Mon, 7 = Sun
    dayname(d.date_day)                                         as day_name,
    dayofweekiso(d.date_day) in (6, 7)                          as is_weekend,
    case
        when month(d.date_day) in (12, 1, 2) then 'Winter'
        when month(d.date_day) in (3, 4, 5)  then 'Spring'
        when month(d.date_day) in (6, 7, 8)  then 'Summer'
        else 'Autumn'
    end                                                         as season,           -- meteorological seasons
    h.holiday_date is not null                                  as is_holiday,
    h.holiday_name,
    dayofweekiso(d.date_day) between 1 and 5
        and h.holiday_date is null                              as is_working_day

from days d
left join holidays h
    on h.holiday_date = d.date_day
