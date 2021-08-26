create table public.infection_time as (
	with a as (
		select 
			stay_id, 
			hr, 
			starttime, 
			sofa_24hours as sofa
		from 
			sepsis.sofa
	),
	c as (
		select 
			stay_id,
			max(suspected_infection) suspected_infection,
			min(suspected_infection_time) suspected_infection_time
		from sepsis.suspicion_of_infection s
		where 
			stay_id is not null and
			suspected_infection = 1
		group by stay_id
	),
	d as (
		select 
			a.stay_id,
			a.hr,
			a.starttime,
			c.suspected_infection_time,
			a.sofa,
			c.suspected_infection
		from a
		left join c
			on a.stay_id = c.stay_id
		where 
			suspected_infection_time - interval '48 hours' <= starttime and
			starttime <= suspected_infection_time + interval '24 hours'
	),
	f as (
		select
			stay_id,
			min(hr) as tractable_time,
			min(starttime) as infection_time
		from d
		where sofa>=3
		group by stay_id
	)
	select *
	from f
	where tractable_time >= 24
)