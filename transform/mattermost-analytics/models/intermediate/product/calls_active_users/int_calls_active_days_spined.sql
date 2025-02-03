{{
    config({
        "materialized": "table",
        "unique_key": ['daily_user_id'],
        "cluster_by": ['activity_date', 'server_id']
    })
}}

with server_first_day_per_telemetry as (
    select
        server_id,
        min(activity_date) as first_active_date,
        max(activity_date) as last_active_date
    from
        {{ ref('int_calls_client_active_days') }}
    where
        activity_date >= '{{ var('calls_telemetry_start_date')}}'
    group by 1
), server_activity_date_range as (
    select
        server_id,
        min(first_active_date) as first_active_date,
        max(last_active_date) as last_active_date
    from
        server_first_day_per_telemetry
    group by
        server_id
), spined as (
    -- Use date spine to fill in missing days
    select
        sadr.server_id,
        all_days.date_day::date as activity_date,
        {{ dbt_utils.generate_surrogate_key(['server_id', 'activity_date']) }} AS daily_server_id
    from
        server_activity_date_range sadr
        left join {{ ref('telemetry_days') }} all_days
            on all_days.date_day >= sadr.first_active_date and all_days.date_day <= sadr.last_active_date
)
select
    s.daily_server_id,
    s.server_id,
    s.activity_date,

    -- Telemetry information
    coalesce(t.daily_active_users, 0) as daily_active_users,
    coalesce(t.weekly_active_users, 0) as weekly_active_users,
    coalesce(t.monthly_active_users, 0) as monthly_active_users

from
    spined s
    left join {{ ref('int_calls_client_active_days') }} t on s.daily_server_id = t.daily_server_id
where
    s.server_id is not null