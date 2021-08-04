/*
qSOFA 기준에 맞추어서 테이블 생성
*/

-- 1. new_sofa(1시간 단위로 나누어진 데이터)에서 qSOFA 진단기준에서 사용하는 데이터(sbp, gcs_min) 합쳐서 사용
create temp table qsofa_temp as
select n.stay_id, hr, starttime, endtime, 
avg(v.sbp) as sbp, 
min(gcs_min) as gcs_min
from public.new_sofa n
left join sepsis.vitalsign v 
on v.charttime > n.starttime and v.charttime <= n.endtime and n.stay_id = v.stay_id
group by n.stay_id, hr, starttime, endtime;

-- 2. new_sofa(1시간 단위로 나누어진 데이터)에서 qSOFA 진단기준에서 사용하는 데이터(respiratory_rate) 합쳐서 사용
create temp table qsofa as
select qt.stay_id, hr, starttime, endtime, avg(qt.sbp) as sbp, 
min(gcs_min) as gcs_min, avg(c.valuenum) as respiratory_rate
from qsofa_temp qt
left join icu.chartevents c 
on c.itemid in (220210, 224422, 224689, 224690) and c.stay_id = qt.stay_id and 
c.charttime > qt.starttime and c.charttime <= qt.endtime 
group by qt.stay_id, hr, starttime, endtime;

-- create temp table qsofa_nan as
-- select *,
-- coalesce(sbp, avg(sbp) over(partition by stay_id order by hr rows between 3 PRECEDING AND CURRENT ROW)) as sbp_na,
-- coalesce(gcs_min, min(gcs_min) over(partition by stay_id order by hr rows between 3 PRECEDING AND CURRENT ROW)) as gcs_na,
-- coalesce(respiratory_rate, avg(respiratory_rate) over(partition by stay_id order by hr rows between 3 PRECEDING AND CURRENT row)) as rr_na
-- from qsofa q

-- create temp table qsofa_score as
-- select *,
-- (sbp <= 100)::int as sbp_score, 
-- (gcs_min <= 14)::int as gcs_score, 
-- (respiratory_rate >= 22)::int as rr_score
-- from qsofa

create table public.qsofa as
select * from qsofa

-- 3. abp_mean, heart_rate, SaO2의 값을 chartevents에서 뽑아내는 테이블
create temp table chartevent as
select subject_id, hadm_id, stay_id, charttime, 
avg(case when itemid = 220052 then valuenum end) as abp_mean,
avg(case when itemid = 220045 then valuenum end) as heart_rate,
avg(case when itemid in (220227, 220277) then valuenum end) as SaO2
from icu.chartevents c
where itemid in (220052, 220045, 220227, 220277)
group by subject_id, hadm_id, stay_id, charttime 

-- 4. icd 진단코드를 붙이기 위해서
-- 	4-1. chartevents에서 subject_id, hadm_id, stay_id의 쌍 한 쌍씩만 가진다
create temp table ids as
select distinct subject_id, hadm_id, stay_id 
from icu.chartevents c 

-- 	4-2. qsofa 테이블에 subject_id, hadm_id, stay_id 합하기
create temp table qsofa_ids as
select i.subject_id, i.hadm_id, q.* from public.qsofa q
left join ids i
on q.stay_id = i.stay_id

-- 5. qsofa_ids와 chartevent 테이블 (4-2와 3번 테이블)을 합한 뒤 fio2를 합하는 테이블
create temp table qsofa_all as
with qsofa_sum as
(
	select q.subject_id, q.hadm_id, q.stay_id, q.starttime, q.endtime, q.hr, 
	q.sbp, q.gcs_min, q.respiratory_rate, abp_mean, heart_rate, SaO2
	from qsofa_ids q 
	left join chartevent c
	on q.subject_id = c.subject_id and q.hadm_id = c.hadm_id and q.stay_id = c.stay_id and c.charttime > q.starttime and c.charttime <= q.endtime 
)
select qs.*, fio2
from qsofa_sum qs 
left join sepsis.bg b 
on b.subject_id = qs.subject_id and b.hadm_id = qs.hadm_id and b.charttime > qs.starttime and b.charttime <= qs.endtime

-- 6. subject_id, hadm_id, stay_id로 묶어 avg값으로 나타내는 테이블
create table public.qsofa_features as
select subject_id, hadm_id, stay_id, hr, starttime, endtime,
avg(sbp) as sbp, min(gcs_min) as gcs_min, avg(respiratory_rate) as respiratory_rate, 
avg(abp_mean) as abp_mean, avg(heart_rate) as heart_rate, avg(SaO2) as SaO2, avg(fio2) as fio2
from qsofa_all
group by subject_id, hadm_id, stay_id, starttime, endtime, hr

-- 4-3. 전체 테이블에서(6번 테이블) icd 코드를 합하여 그 값이 있는 경우(진단을 받은 경우) 1, 아닌 경우 0을 return 하여 테이블 완성
create table public.qsofa_icdcode as
select distinct qf.*, (case when di.icd_code is null then 0 else 1 end) as icd_event from public.qsofa_features qf
left join hosp.diagnoses_icd di 
on qf.subject_id = di.subject_id and qf.hadm_id = di.hadm_id and di.icd_code in  ('99592', 'R652', 'R6520', 'R6521')
