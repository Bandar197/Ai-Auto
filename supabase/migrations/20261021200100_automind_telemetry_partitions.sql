-- =============================================================================
-- AutoMind AI — telemetry time-series storage (migration 2/4)
--
-- Strategy
--   * automind.telemetry_readings is range-partitioned by month on `ts`.
--   * Each partition gets a BRIN index on ts (tiny, ideal for append-only data)
--     — the composite PK already serves per-session lookups.
--   * Retention: partitions older than the retention window are detached and
--     dropped. Long-term value is kept in telemetry_aggregates (per-session
--     statistics) and in archived recordings (object storage).
--   * ensure_telemetry_partitions() is idempotent; call it from the backend at
--     start-up and daily (or schedule it with pg_cron where available).
-- =============================================================================

create or replace function automind.ensure_telemetry_partitions(months_back int default 1, months_ahead int default 3)
returns int
language plpgsql
set search_path = ''
as $$
declare
  m        date;
  first_m  date := (date_trunc('month', now()) - make_interval(months => months_back))::date;
  last_m   date := (date_trunc('month', now()) + make_interval(months => months_ahead))::date;
  part     text;
  created  int := 0;
begin
  m := first_m;
  while m <= last_m loop
    part := format('telemetry_readings_%s', to_char(m, 'YYYY_MM'));
    if to_regclass(format('automind.%I', part)) is null then
      execute format(
        'create table automind.%I partition of automind.telemetry_readings for values from (%L) to (%L)',
        part, m::timestamptz, (m + interval '1 month')::timestamptz);
      execute format('create index %I on automind.%I using brin (ts)', part || '_ts_brin', part);
      execute format('alter table automind.%I enable row level security', part);
      created := created + 1;
    end if;
    m := (m + interval '1 month')::date;
  end loop;
  return created;
end;
$$;

-- Catch-all so an out-of-window timestamp (e.g. device clock wrong) never
-- breaks ingestion; the backend also rejects implausible timestamps.
create table if not exists automind.telemetry_readings_default
  partition of automind.telemetry_readings default;
alter table automind.telemetry_readings_default enable row level security;

create or replace function automind.drop_old_telemetry_partitions(retain_months int default 6)
returns int
language plpgsql
set search_path = ''
as $$
declare
  r        record;
  cutoff   date := (date_trunc('month', now()) - make_interval(months => retain_months))::date;
  dropped  int := 0;
  part_month date;
begin
  if retain_months < 1 then
    raise exception 'retain_months must be >= 1';
  end if;
  for r in
    select c.relname
    from pg_inherits i
    join pg_class c on c.oid = i.inhrelid
    join pg_class p on p.oid = i.inhparent
    join pg_namespace n on n.oid = p.relnamespace
    where n.nspname = 'automind' and p.relname = 'telemetry_readings'
      and c.relname ~ '^telemetry_readings_[0-9]{4}_[0-9]{2}$'
  loop
    part_month := to_date(right(r.relname, 7), 'YYYY_MM');
    if part_month < cutoff then
      execute format('alter table automind.telemetry_readings detach partition automind.%I', r.relname);
      execute format('drop table automind.%I', r.relname);
      dropped := dropped + 1;
    end if;
  end loop;
  return dropped;
end;
$$;

-- Roll raw samples of one session into telemetry_aggregates.
create or replace function automind.refresh_session_aggregates(p_session_id uuid)
returns int
language sql
set search_path = ''
as $$
  with agg as (
    insert into automind.telemetry_aggregates as a
      (session_id, signal, pid, unit, sample_count, min_value, max_value, avg_value, stddev_value, first_ts, last_ts)
    select session_id, signal, min(pid), min(unit), count(*), min(value), max(value), avg(value),
           stddev_samp(value), min(ts), max(ts)
    from automind.telemetry_readings
    where session_id = p_session_id
    group by session_id, signal
    on conflict (session_id, signal) do update set
      pid = excluded.pid, unit = excluded.unit, sample_count = excluded.sample_count,
      min_value = excluded.min_value, max_value = excluded.max_value, avg_value = excluded.avg_value,
      stddev_value = excluded.stddev_value, first_ts = excluded.first_ts, last_ts = excluded.last_ts
    returning 1
  )
  select count(*)::int from agg;
$$;

select automind.ensure_telemetry_partitions(1, 3);
