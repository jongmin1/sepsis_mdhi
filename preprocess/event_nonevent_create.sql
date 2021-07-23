/*
8시간 단위로 데이터를 묶어 정상 환자와 발병 환자를 나누어 저장하는 테이블.

public.sofa_8
	stay_id 와 hr 를 기준으로 0시간씩 묶어서 feature의 값을 avg로 나타낸 테이블

public.realage
	icu.icustays 테이블을 기준으로 나이 계산

public.event_table
	발병 환자 테이블
	infection_time: 감염 시각
	is_infection: 감염되었는지 여부 -- 감염 시각이 starttime과 endtime 사이에 있는 경우에만 기입. 아닌 경우 null
	infection_hour: (심박수 최초 기록 시각 기준) 감염된 시간 -- 감염 시각이 starttime과 endtime 사이에 있는 경우에만 기입. 아닌 경우 null

public.nonevent_table
	정상 환자 테이블
	데이터가 32시간 미만으로 기록된 경우 삭제
*/

-- 8시간 단위로 나누기 
create temp table sofa_hr as
select *, (hr/8-0.45)::int as compiled_hr from sepsis.sofa s ;

create table public.sofa_8 as
select stay_id, compiled_hr, min(starttime) as starttime, max(endtime) as endtime, 
	avg(pao2fio2ratio_novent) as pao2fio2ratio_novent, avg(pao2fio2ratio_vent) as pao2fio2ratio_vent,
	avg(rate_dobutamine) as rate_dobutamine, avg(rate_dopamine) as rate_dopamine, avg(rate_epinephrine) as rate_epinephrine, 
	avg(rate_norepinephrine) as rate_norepinephrine, avg(meanbp_min) as meanbp_min, min(gcs_min) as gcs_min,
	avg(bilirubin_max) as bilirubin_max, avg(creatinine_max) as creatinine_max, avg(platelet_min) as platelet_min,
	avg(respiration) as respiration, avg(coagulation) as coagulation, avg(liver) as liver, avg(cns) as cns, avg(renal) as renal, 
	max(respiration_24hours) as respiration_24hours, max(coagulation_24hours) as coagulation_24hours, max(liver_24hours) as liver_24hours, 
	max(cns_24hours) as cns_24hours, max(renal_24hours) as renal_24hours, max(sofa_24hours) as sofa_24hours
from sofa_hr
group by stay_id, compiled_hr;

-- icustays에 맞추어서 실제 나이 계산 
create temp table startyear as
select distinct i.subject_id, i.hadm_id, ns.stay_id, substring(starttime::text, 0, 5) as startyear from public.new_sofa_8 ns
left join icu.icustays i 
on ns.stay_id = i.stay_id ;

create table public.realage as
select distinct s.subject_id, s.hadm_id, s.stay_id, (s.startyear::int - p.anchor_year + p.anchor_age)::int as realage, 
s.startyear as curryear, p.anchor_year as anchor_year from core.patients p 
right join startyear s 
on p.subject_id = s.subject_id;


-- icd code ('99592', 'R652', 'R6520', 'R6521') 진단 받은 환자 중 미생물 검사를 받은 환자
-- 	--> 발병 환자와 정상 환자 나누어 테이블 저장 

-- 발병 환자 
--	1. 발병 환자 subject_id, stay_id 추출 
create table public.infection as
with s as (
	select 
		subject_id,
		hadm_id,
		min(suspected_infection_time) as infection_time
	from sepsis.suspicion_of_infection 
	where suspected_infection = 1
	group by subject_id, hadm_id
)
select
	distinct s.subject_id,
	r.stay_id,
	s.infection_time
from 
	s inner join public.realage r
	on (s.subject_id = r.subject_id and s.hadm_id = r.hadm_id)
	inner join hosp.diagnoses_icd d
	on s.subject_id = d.subject_id
where 
	d.icd_code in  ('99592', 'R652', 'R6520', 'R6521');

--	2. 정상 환자테이블 이용하여 sofa_table에서 데이터 추출 (발병 시간에 따라 추출)  
create table public.event_table as
select i.subject_id, ns.*, i.infection_time, 
(case when i.infection_time between ns.starttime and ns.endtime then 1 else null end) as is_infection,
(case when i.infection_time between ns.starttime and ns.endtime then 
ns.compiled_hr*8+(EXTRACT(epoch from (i.infection_time - ns.starttime))/3600-0/5)::int else null end) as infection_hour
from public.new_sofa_8 ns 
join public.infection i 
on ns.stay_id = i.stay_id;

-- 정상 환자 
-- 	1. 정상 환자 subject_id, stay_id 추출 
create temp table nonevent_age as
select t.subject_id, t.stay_id from public.realage t 
where t.subject_id in ( 
	select distinct a.subject_id from sepsis.suspicion_of_infection a
	where a.suspected_infection=0 and a.subject_id not in (
		select d.subject_id from hosp.diagnoses_icd d 
		where d.icd_code in ('99592', 'R652', 'R6520', 'R6521')
		)
	);

-- 	2. 정상 환자테이블 이용하여 sofa_table에서 데이터 추출 
create table public.nonevent_table_all as
select ns.* 
from public.new_sofa_8 ns 
join nonevent_age ea 
on ns.stay_id = ea.stay_id;

-- 	3. 32시간 미만으로 존재하는 환자데이터 삭제 
create table public.nonevent_table as 
select count(distinct stay_id) as stay_id, count(*) as all
from public.nonevent_table_all et
where et.stay_id in (
	select stay_id
	from public.nonevent_table_all
	where compiled_hr = 4);

