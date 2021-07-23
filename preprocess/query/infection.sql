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
    d.icd_code in  ('99592', 'R652', 'R6520', 'R6521')