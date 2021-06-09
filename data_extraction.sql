--latest version

--FIRST THING: CALCULATE AGE OF PATIENT FOR EACH ICUSTAY_ID
SELECT I.ICUSTAY_ID, I.HADM_ID, P.GENDER, P.EXPIRE_FLAG as DEAD, I.INTIME, I.OUTTIME, (INTIME::date - DOB::date)/365 as AGE
INTO ISABELA.ICUSTAYS_PAT 
FROM MIMIC_UNTOUCHED.ICUSTAYS I  INNER JOIN  MIMIC_UNTOUCHED.PATIENTS P  on I.SUBJECT_ID = P.SUBJECT_ID 
WHERE P.DOB < I.INTIME 
    and I.ICUSTAY_ID IS NOT NULL 
    AND (I.INTIME::date - P.DOB::date)/365 BETWEEN 14 and 89
GROUP BY I.ICUSTAY_ID, I.HADM_ID, P.GENDER, P.EXPIRE_FLAG,I.INTIME, I.OUTTIME,P.DOB
ORDER BY I.ICUSTAY_ID;
--50711 


--WEIGHTS X ICUSTAY_ID
DROP TABLE IF EXISTS ISABELA.WEIGHTS;
SELECT I.ICUSTAY_ID, AVG(C.VALUENUM) AS AVG_WEIGHT
INTO ISABELA.WEIGHTS
FROM MIMIC_UNTOUCHED.CHARTEVENTS C JOIN ISABELA.ICUSTAYS_PAT I ON  C.ICUSTAY_ID = I.ICUSTAY_ID
WHERE  I.AGE BETWEEN 14 AND 89 --IN PIU'
	AND C.VALUENUM IS NOT NULL
	AND C.VALUENUM > 0 
	AND	C.ITEMID IN (224639,3693,763,581,580) 
GROUP BY I.ICUSTAY_ID
ORDER BY I.ICUSTAY_ID; 
--30.845


---------------------------------------------------------------------------------------------------------

--1st CRITERION : Scr increase of at least 0.3 within 48h 
--TAKE ALL Scr MEASUREMENTS TO INPUT INTO KNIME FOR THE WINDOW LOOP 
DROP TABLE IF EXISTS ISABELA.INPUT_KNIME_SCR;
SELECT DISTINCT IP.ICUSTAY_ID, L.CHARTTIME, L.VALUENUM, IP.INTIME, IP.OUTTIME 
INTO ISABELA.INPUT_KNIME_SCR
FROM MIMIC_UNTOUCHED.LABEVENTS L JOIN ISABELA.ICUSTAYS_PAT IP ON L.HADM_ID = IP.HADM_ID
WHERE   L.ITEMID = 50912 --CREATININE
	AND L.CHARTTIME >= IP.INTIME AND L.CHARTTIME <= IP.OUTTIME 
	AND L.VALUENUM  IS NOT NULL 
	AND IP.ICUSTAY_ID IS NOT NULL 
	AND IP.AGE BETWEEN 14 AND 89
ORDER BY IP.ICUSTAY_ID, L.CHARTTIME; 
--311.669


-- in knime: TABLE => ISABELA.AKI_1COND
-- 11.185 AKI 

---------------------------------------------------------------------------------------------------------

--2nd CRITERION: Scr >= 1.5*BASELINE, WHERE BASELINE = AVG(SCR) IN THE 7 DAYS PREVIOUS ICU ADMISSION
DROP TABLE IF EXISTS ISABELA.AVG_SCR_BEFOREICU;
SELECT IP.ICUSTAY_ID, ROUND(CAST(AVG(L.VALUENUM) AS NUMERIC),2) AS BASELINE 
INTO ISABELA.AVG_SCR_BEFOREICU
FROM MIMIC_UNTOUCHED.LABEVENTS L JOIN ISABELA.ICUSTAYS_PAT IP ON L.HADM_ID = IP.HADM_ID
WHERE L.ITEMID = 50912 --CREATININE
	AND IP.AGE BETWEEN 14 AND 89 
    AND L.VALUENUM IS NOT NULL 
	AND L.HADM_ID IS NOT NULL 
	AND (L.CHARTTIME < IP.INTIME AND L.CHARTTIME >= (IP.INTIME - INTERVAL '7 DAY'))
GROUP BY IP.ICUSTAY_ID
ORDER BY IP.ICUSTAY_ID;
--41.138
 

DROP TABLE IF EXISTS ISABELA.AKI_2COND;
SELECT  IP.ICUSTAY_ID, MIN(L.CHARTTIME) AS CHARTTIME_OF_AKI
INTO ISABELA.AKI_2COND 
FROM MIMIC_UNTOUCHED.LABEVENTS L JOIN ISABELA.ICUSTAYS_PAT IP ON L.HADM_ID = IP.HADM_ID
	JOIN ISABELA.AVG_SCR_BEFOREICU AC ON IP.ICUSTAY_ID = AC.ICUSTAY_ID
WHERE L.ITEMID = 50912 --CREATININE 
    AND L.VALUENUM IS NOT NULL 
	AND L.CHARTTIME >= IP.INTIME 
    AND L.CHARTTIME <= IP.OUTTIME
	AND L.VALUENUM >= 1.5*AC.BASELINE
	AND IP.AGE BETWEEN 14 AND 89 
GROUP BY IP.ICUSTAY_ID
ORDER BY IP.ICUSTAY_ID;
--3966 AKI 
 

---------------------------------------------------------------------------------------------------------

--3rd CRITERION : URINES OUTPUT/KG < 0.5 WITHIN 6H 
--TAKE ALL URINES MEASUREMENTS TO INPUT INTO KNIME FOR THE WINDOW LOOP 
DROP TABLE IF EXISTS ISABELA.INPUT_KNIME_URINES;
SELECT DISTINCT O.ICUSTAY_ID, O.CHARTTIME, O.VALUE,  W.AVG_WEIGHT
INTO ISABELA.INPUT_KNIME_URINES
FROM MIMIC_UNTOUCHED.OUTPUTEVENTS O JOIN ISABELA.WEIGHTS W ON O.ICUSTAY_ID = W.ICUSTAY_ID
	JOIN ISABELA.ICUSTAYS_PAT IP ON O.ICUSTAY_ID = IP.ICUSTAY_ID
WHERE   O.ITEMID IN (40055,43175,40069,40094,40715,40473,40085,40057,40056,
				   40405,40428,40086,40096,40651,226559,226560,226561,226584,
				   226563,226564,226565,226567,226557,226558,227488,227489)
	AND O.CHARTTIME >= IP.INTIME AND O.CHARTTIME <= IP.OUTTIME 
	AND O.VALUE  IS NOT NULL 
	AND O.ICUSTAY_ID IS NOT NULL 
	AND IP.AGE BETWEEN 14 AND 89
ORDER BY O.ICUSTAY_ID, O.CHARTTIME; 
--2.581.934


SELECT DISTINCT  ICUSTAY_ID
FROM ISABELA.INPUT_KNIME_URINES;
--29561


--DONE IN KNIME WORKFLOW: TABLE AKI_3COND
--IMPORT TABLE AKI_3COND INTO SERVER.
SELECT DISTINCT COUNT (ICUSTAY_ID)
FROM ISABELA.AKI_3COND;
--21887 WITH ALSO VALUES FOR VOLUME_PER_H_KG = 0


select * from isabela.aki_3cond a join isabela.icustays_pat i on a.icustay_id = i.icustay_id
where i.outtime-i.intime < interval '6 hour';
--3 

update isabela.aki_3cond 
set charttime_of_aki = '2200-04-01 07:00:00',
	volume_per_h_kg = 0.4761904761904762
where icustay_id = 203920;

update isabela.aki_3cond 
set charttime_of_aki = '2152-03-25 22:45:00',
	volume_per_h_kg = 0.4762264735177714
where icustay_id = 214810;
---------------------------------------------------------------------------------------------------------------------
--put together all AKI  AFTER THE FIRST 24H IN ICU 
DROP TABLE IF EXISTS ISABELA.AKI_AFTER24H ;
SELECT C1.ICUSTAY_ID, min(C1.CHARTTIME_OF_AKI) AS CHARTTIME_OF_AKI
INTO ISABELA.AKI_AFTER24H
FROM ISABELA.AKI_1COND C1 JOIN ISABELA.ICUSTAYS_PAT IP 
	ON C1.ICUSTAY_ID = IP.ICUSTAY_ID
WHERE C1.CHARTTIME_OF_AKI > IP.INTIME + INTERVAL '24 HOUR' 
GROUP BY C1.ICUSTAY_ID
union 
SELECT  C2.ICUSTAY_ID, min(C2.CHARTTIME_OF_AKI) AS CHARTTIME_OF_AKI
FROM ISABELA.AKI_2COND C2 JOIN ISABELA.ICUSTAYS_PAT IP1 
	ON C2.ICUSTAY_ID = IP1.ICUSTAY_ID
WHERE C2.CHARTTIME_OF_AKI > IP1.INTIME + INTERVAL '24 HOUR'
GROUP BY C2.ICUSTAY_ID
union 
SELECT U.ICUSTAY_ID, min(U.CHARTTIME_OF_AKI) AS CHARTTIME_OF_AKI
FROM ISABELA.AKI_3COND U JOIN ISABELA.ICUSTAYS_PAT IP2 
	ON U.ICUSTAY_ID = IP2.ICUSTAY_ID
WHERE U.CHARTTIME_OF_AKI > IP2.INTIME + INTERVAL '24 HOUR'
GROUP BY U.ICUSTAY_ID; 
-- 14640


--TOT AKI IN ICU 
DROP TABLE IF EXISTS ISABELA.AKI ;
SELECT  C1.ICUSTAY_ID, C1.CHARTTIME_OF_AKI
INTO ISABELA.AKI
FROM ISABELA.AKI_1COND C1 
union 
SELECT  C2.ICUSTAY_ID,C2.CHARTTIME_OF_AKI
FROM ISABELA.AKI_2COND C2 
union 
SELECT  U.ICUSTAY_ID, U.CHARTTIME_OF_AKI
FROM ISABELA.AKI_3COND U ; 
--35863 with those within 24h


--RETRIEVE ALL AKI X ICUSTAY_ID 
DROP TABLE IF EXISTS ISABELA.AKI_DISTINCT ;
SELECT ICUSTAY_ID, MIN(CHARTTIME_OF_AKI) AS CHARTTIME_OF_AKI
INTO ISABELA.AKI_DISTINCT 
FROM ISABELA.AKI 
GROUP BY ICUSTAY_ID;
--25740 aki tot with those within 24h 

----------------------------------------------------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS ISABELA.ICUSTAYS_PAT_FLAG;
SELECT  ICUSTAY_ID, AGE, GENDER, DEAD, INTIME, OUTTIME, HADM_ID,
CASE
	WHEN ICUSTAY_ID IN ( SELECT A.ICUSTAY_ID
						   FROM ISABELA.AKI_DISTINCT A  )
		THEN '1'::INTEGER 
	ELSE '0'::INTEGER
	END AS AKI_FLAG
INTO ISABELA.ICUSTAYS_PAT_FLAG
FROM  ISABELA.ICUSTAYS_PAT I --50711 TOT DI PARTENZA 
WHERE AGE BETWEEN 14 AND 89
ORDER BY I.ICUSTAY_ID;
--50711 TOT 
--IMPORTED INTO KNIME AND MODIFIED AS FOLLOWS: 
	-- TAKE THE CHARTTIME_OF_AKI FOR EACH AKI_FLAG = 1 (LEFT OUTER JOIN BETWEEN ICUSTAYS_PAT AND AKI_DISTINCT)
	-- MANTAIN CHARTTIME_OF_AKI NULL FOR EACH AKI_FLAG = 0 

SELECT * FROM  ISABELA.ICUSTAYS_PAT_FLAG
WHERE AKI_FLAG = 1;
--25740 TOT 

SELECT * FROM  ISABELA.ICUSTAYS_PAT_FLAG
WHERE AKI_FLAG = 0;
--24971


---------------------------------------------------------------------------------------------------------------------------------------------
-- COUNT AKI/NON-AKI IN THE DIFFERENT TIME INTERVALS 
---------------------------------------------------------------------------------------------------------------------------------------------

--CALCULATE ALL AKI IN 24H - (24H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '24 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '24 HOUR' + INTERVAL '168 HOUR';
--7337

--CALCULATE ALL AKI IN 48H - (48H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '48 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '48 HOUR' + INTERVAL '168 HOUR';
--2380

-- DOING IT TOGETHER for aki/non-aki 
--CALCULATE ALL AKI/NON-AKI IN 24H - (24H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '24 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '24 HOUR' + INTERVAL '168 HOUR'
UNION ALL
SELECT COUNT ( ICUSTAY_ID)
FROM ISABELA.ICUSTAYS_PAT_FLAG F
WHERE AKI_FLAG = 0 AND OUTTIME > INTIME + INTERVAL '24 HOUR'
	OR ( AKI_FLAG = 1 AND  CHARTTIME_OF_AKI >= INTIME + INTERVAL '24 HOUR' + INTERVAL '168 HOUR');
--7337
--18834

--CALCULATE ALL AKI/NON-AKI  IN 48H - (48H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '48 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '48 HOUR' + INTERVAL '168 HOUR'
UNION ALL
SELECT COUNT ( ICUSTAY_ID)
FROM ISABELA.ICUSTAYS_PAT_FLAG F
WHERE AKI_FLAG = 0 AND OUTTIME > INTIME + INTERVAL '48 HOUR'
	OR ( AKI_FLAG = 1 AND  CHARTTIME_OF_AKI >= INTIME + INTERVAL '48 HOUR' + INTERVAL '168 HOUR');
--2380
--8378

--CALCULATE ALL AKI/NON-AKI  IN 72H - (72H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '72 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '72 HOUR' + INTERVAL '168 HOUR'
UNION ALL
SELECT COUNT ( ICUSTAY_ID)
FROM ISABELA.ICUSTAYS_PAT_FLAG F
WHERE AKI_FLAG = 0 AND OUTTIME > INTIME + INTERVAL '72 HOUR'
	OR ( AKI_FLAG = 1 AND  CHARTTIME_OF_AKI >= INTIME + INTERVAL '72 HOUR' + INTERVAL '168 HOUR');
--1134
--4119

--CALCULATE ALL AKI/NON-AKI  IN 96H - (96H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '96 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '96 HOUR' + INTERVAL '168 HOUR'
UNION ALL
SELECT COUNT ( ICUSTAY_ID)
FROM ISABELA.ICUSTAYS_PAT_FLAG F
WHERE AKI_FLAG = 0 AND OUTTIME > INTIME + INTERVAL '96 HOUR'
	OR ( AKI_FLAG = 1 AND  CHARTTIME_OF_AKI >= INTIME + INTERVAL '96 HOUR' + INTERVAL '168 HOUR');
--640
--2322

--CALCULATE ALL AKI/NON-AKI  IN 120H - (120H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '120 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '120 HOUR' + INTERVAL '168 HOUR'
UNION ALL
SELECT COUNT ( ICUSTAY_ID)
FROM ISABELA.ICUSTAYS_PAT_FLAG F
WHERE AKI_FLAG = 0 AND OUTTIME > INTIME + INTERVAL '120 HOUR'
	OR ( AKI_FLAG = 1 AND  CHARTTIME_OF_AKI >= INTIME + INTERVAL '120 HOUR' + INTERVAL '168 HOUR');
--437
--1473

--CALCULATE ALL AKI/NON-AKI  IN 144H - (144H+7DAYS) TIME PERIOD 
SELECT COUNT ( ICUSTAY_ID )
FROM  ISABELA.ICUSTAYS_PAT_FLAG F  
WHERE AKI_FLAG = 1 AND 
	  CHARTTIME_OF_AKI > INTIME + INTERVAL '144 HOUR' AND 
	  CHARTTIME_OF_AKI <= INTIME + INTERVAL '144 HOUR' + INTERVAL '168 HOUR'
UNION ALL
SELECT COUNT ( ICUSTAY_ID)
FROM ISABELA.ICUSTAYS_PAT_FLAG F
WHERE AKI_FLAG = 0 AND OUTTIME > INTIME + INTERVAL '144 HOUR'
	OR ( AKI_FLAG = 1 AND  CHARTTIME_OF_AKI >= INTIME + INTERVAL '144 HOUR' + INTERVAL '168 HOUR');
--312
--1034
--------------------------------------------------------------------------------------------------

---------------|----------|---------|----------|----------|----------|---------|
--             |  24H     |  48H    |   72H    |    96H   |   120H   |  144H   |
---------------|----------|---------|----------|----------|----------|---------|
--   AKI       |  7337    |  2380   |   1134   |   640    |   437    |  312    |
---------------|----------|---------|----------|----------|----------|---------|
--   NON AKI   |  18834   |  8378   |   4119   |   2322   |   1473   |  1034   |
---------------|----------|---------|----------|----------|----------|---------|
--  TOT        |   26171  |  10758  |  5253    |  2962    |   1910   |  1346   |
---------------|----------|---------|----------|----------|----------|---------|

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------

--DROP TABLE IF EXISTS ISABELA.DATA_24H;
SELECT ICUSTAY_ID, AKI_FLAG, GENDER, AGE, DEAD, HADM_ID, INTIME, OUTTIME, 
CASE WHEN ICUSTAY_ID IN (SELECT I.ICUSTAY_ID FROM ISABELA.ICUSTAYS_PAT_FLAG I
						  WHERE I.AKI_FLAG=1 AND I.CHARTTIME_OF_AKI > I.INTIME + INTERVAL '24 HOUR' 
						  AND I.CHARTTIME_OF_AKI <= I.INTIME + INTERVAL '24 HOUR' + INTERVAL '168 HOUR' )
	THEN '1' ELSE '0'
END AS AKI_PWD

FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME <= INTERVAL '24 HOUR' --stayed in icu max 24h
	AND AKI_FLAG = 0;
--6367

--DROP TABLE IF EXISTS ISABELA.DATA_48H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, AGE, DEAD, HADM_ID, INTIME, OUTTIME, 
CASE WHEN ICUSTAY_ID IN (SELECT I.ICUSTAY_ID FROM ISABELA.ICUSTAYS_PAT_FLAG I
						  WHERE I.AKI_FLAG=1 AND I.CHARTTIME_OF_AKI > I.INTIME + INTERVAL '48 HOUR' 
						  AND I.CHARTTIME_OF_AKI <= I.INTIME + INTERVAL '48 HOUR' + INTERVAL '168 HOUR' )
	THEN '1' ELSE '0'
END AS AKI_PWD
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME <= INTERVAL '48 HOUR' --stayed in icu max 120H
	AND OUTTIME-INTIME > INTERVAL '24 HOUR'
	AND AKI_FLAG = 0;
--10408

--DROP TABLE IF EXISTS ISABELA.DATA_72H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, AGE, DEAD, HADM_ID, INTIME, OUTTIME, 
CASE WHEN ICUSTAY_ID IN (SELECT I.ICUSTAY_ID FROM ISABELA.ICUSTAYS_PAT_FLAG I
						  WHERE I.AKI_FLAG=1 AND I.CHARTTIME_OF_AKI > I.INTIME + INTERVAL '72 HOUR' 
						  AND I.CHARTTIME_OF_AKI <= I.INTIME + INTERVAL '72 HOUR' + INTERVAL '168 HOUR' )
	THEN '1' ELSE '0'
END AS AKI_PWD

FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME <= INTERVAL '72 HOUR' --stayed in icu max 120H
	AND OUTTIME-INTIME > INTERVAL '48 HOUR'
	AND AKI_FLAG = 0;
--4220

--DROP TABLE IF EXISTS ISABELA.DATA_96H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, AGE, DEAD, HADM_ID, INTIME, OUTTIME, 
CASE WHEN ICUSTAY_ID IN (SELECT I.ICUSTAY_ID FROM ISABELA.ICUSTAYS_PAT_FLAG I
						  WHERE I.AKI_FLAG=1 AND I.CHARTTIME_OF_AKI > I.INTIME + INTERVAL '96 HOUR' 
						  AND I.CHARTTIME_OF_AKI <= I.INTIME + INTERVAL '96 HOUR' + INTERVAL '168 HOUR' )
	THEN '1' ELSE '0'
END AS AKI_PWD

FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME <= INTERVAL '96 HOUR' --stayed in icu max 120H
	AND OUTTIME-INTIME > INTERVAL '72 HOUR'
	AND AKI_FLAG = 0;
--1776

--DROP TABLE IF EXISTS ISABELA.DATA_120H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, AGE, DEAD, HADM_ID, INTIME, OUTTIME, 
CASE WHEN ICUSTAY_ID IN (SELECT I.ICUSTAY_ID FROM ISABELA.ICUSTAYS_PAT_FLAG I
						  WHERE I.AKI_FLAG=1 AND I.CHARTTIME_OF_AKI > I.INTIME + INTERVAL '120 HOUR' 
						  AND I.CHARTTIME_OF_AKI <= I.INTIME + INTERVAL '120 HOUR' + INTERVAL '168 HOUR' )
	THEN '1' ELSE '0'
END AS AKI_PWD
--INTO ISABELA.DATA_120H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME <= INTERVAL '120 HOUR' --stayed in icu max 120H
	AND OUTTIME-INTIME > INTERVAL '96 HOUR'
	AND AKI_FLAG = 0;
--825

--DROP TABLE IF EXISTS ISABELA.DATA_144H;
SELECT *, 
CASE WHEN ICUSTAY_ID IN (SELECT I.ICUSTAY_ID FROM ISABELA.ICUSTAYS_PAT_FLAG I
						  WHERE I.AKI_FLAG=1 AND I.CHARTTIME_OF_AKI > I.INTIME + INTERVAL '144 HOUR' 
						  AND I.CHARTTIME_OF_AKI <= I.INTIME + INTERVAL '144 HOUR' + INTERVAL '168 HOUR' )
	THEN '1' ELSE '0'
END AS AKI_PWD 
--INTO ISABELA.DATA_144H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME <= INTERVAL '144 HOUR' --stayed in icu max 48H
	AND OUTTIME-INTIME > INTERVAL '120 HOUR'
	AND AKI_FLAG = 0;
--423
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
-- CONSIDERING THE STAY LASTING AT LEAST t HOURS and AKI_FLAG = 0 OR 1 IN PW.
DROP TABLE IF EXISTS ISABELA.DATA_24H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, ETHNICITY,AGE, DEAD, HADM_ID, INTIME, OUTTIME
INTO ISABELA.DATA_24H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '24 HOUR' --stayed in icu at least 24H
	AND AKI_FLAG = 0 OR (AKI_FLAG = 1 AND CHARTTIME_OF_AKI > INTIME + INTERVAL '24 HOUR' 
	AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '24 HOUR' + INTERVAL '168 HOUR');
--25940

DROP TABLE IF EXISTS ISABELA.DATA_48H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER,ETHNICITY, AGE, DEAD, HADM_ID, INTIME, OUTTIME
INTO ISABELA.DATA_48H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '48 HOUR' 
	AND AKI_FLAG = 0 OR (AKI_FLAG = 1 AND CHARTTIME_OF_AKI > INTIME + INTERVAL '48 HOUR' 
	AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '48 HOUR' + INTERVAL '168 HOUR');
--10573

DROP TABLE IF EXISTS ISABELA.DATA_72H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, ETHNICITY, AGE, DEAD, HADM_ID, INTIME, OUTTIME
INTO ISABELA.DATA_72H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '72 HOUR' 
	AND AKI_FLAG = 0 OR (AKI_FLAG = 1 AND CHARTTIME_OF_AKI > INTIME + INTERVAL '72 HOUR' 
	AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '72 HOUR' + INTERVAL '168 HOUR');
--5107

DROP TABLE IF EXISTS ISABELA.DATA_96H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER,ETHNICITY, AGE, DEAD, HADM_ID, INTIME, OUTTIME
INTO ISABELA.DATA_96H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '96 HOUR' 
	AND AKI_FLAG = 0 OR (AKI_FLAG = 1 AND CHARTTIME_OF_AKI > INTIME + INTERVAL '96 HOUR' 
	AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '96 HOUR' + INTERVAL '168 HOUR');
--2837

DROP TABLE IF EXISTS ISABELA.DATA_120H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER,ETHNICITY, AGE, DEAD, HADM_ID, INTIME, OUTTIME
INTO ISABELA.DATA_120H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '120 HOUR' 
	AND AKI_FLAG = 0 OR (AKI_FLAG = 1 AND CHARTTIME_OF_AKI > INTIME + INTERVAL '120 HOUR' 
	AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '120 HOUR' + INTERVAL '168 HOUR');
--1809

DROP TABLE IF EXISTS ISABELA.DATA_144H;
SELECT ICUSTAY_ID, AKI_FLAG,GENDER, ETHNICITY, AGE, DEAD, HADM_ID, INTIME, OUTTIME
INTO ISABELA.DATA_144H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '144 HOUR' 
	AND AKI_FLAG = 0 OR (AKI_FLAG = 1 AND CHARTTIME_OF_AKI > INTIME + INTERVAL '144 HOUR' 
	AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '144 HOUR' + INTERVAL '168 HOUR');
--1261



---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---------------|----------|---------|----------|----------|----------|---------|
--             |  24H     |  48H    |   72H    |    96H   |   120H   |  144H   |
---------------|----------|---------|----------|----------|----------|---------|
--   AKI       |  7337    |  2380   |   1134   |   640    |   437    |  312    |
---------------|----------|---------|----------|----------|----------|---------|
--   NON AKI   |  35750   |  25171  |   17545  |   13068  |   10178  |  8310   |
---------------|----------|---------|----------|----------|----------|---------|
--   TOT       |  43087   |  27551  |   18679  |   13708  |   10615  |  8622   |
---------------|----------|---------|----------|----------|----------|---------|

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--CREATE TABLE 24H OF THE  RESULTS TABLE
DROP TABLE IF EXISTS ISABELA.DATA_24H;
SELECT *,
CASE 
	WHEN CHARTTIME_OF_AKI > INTIME + INTERVAL '24 HOUR' 
	 AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '24 HOUR' + INTERVAL  '168 HOUR'
		THEN 1 
	ELSE 0 
END as AKI_7DAYS
INTO ISABELA.DATA_24H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '24 HOUR' 
	AND (CHARTTIME_OF_AKI > INTIME + INTERVAL '24 hour' OR CHARTTIME_OF_AKI ISNULL);
	

--CREATE TABLE FOR COLUMN 48H OF THE  RESULTS TABLE
DROP TABLE IF EXISTS ISABELA.DATA_48H;
SELECT *,
CASE 
	WHEN CHARTTIME_OF_AKI > INTIME + INTERVAL '48 HOUR' 
	 AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '48 HOUR' + INTERVAL  '168 HOUR'
		THEN 1 
	ELSE 0 
END as AKI_7DAYS
INTO ISABELA.DATA_48H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '48 HOUR' 
	AND (CHARTTIME_OF_AKI > INTIME + INTERVAL '48 hour' OR CHARTTIME_OF_AKI ISNULL);
--10758	

--CREATE TABLE FOR COLUMN 72H OF THE  RESULTS TABLE
DROP TABLE IF EXISTS ISABELA.DATA_72H;
SELECT *,
CASE 
	WHEN CHARTTIME_OF_AKI > INTIME + INTERVAL '72 HOUR' 
	 AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '72 HOUR' + INTERVAL  '168 HOUR'
		THEN 1 
	ELSE 0 
END as AKI_7DAYS
INTO ISABELA.DATA_72H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '72 HOUR' 
	AND (CHARTTIME_OF_AKI > INTIME + INTERVAL '72 hour' OR CHARTTIME_OF_AKI ISNULL);
--5253

--CREATE TABLE FOR COLUMN 96H OF THE  RESULTS TABLE
DROP TABLE IF EXISTS ISABELA.DATA_96H;
SELECT *,
CASE 
	WHEN CHARTTIME_OF_AKI > INTIME + INTERVAL '96 HOUR' 
	 AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '96 HOUR' + INTERVAL  '168 HOUR'
		THEN 1 
	ELSE 0 
END as AKI_7DAYS
INTO ISABELA.DATA_96H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '96 HOUR' 
	AND (CHARTTIME_OF_AKI > INTIME + INTERVAL '96 hour' OR CHARTTIME_OF_AKI ISNULL);
--2962

--CREATE TABLE FOR COLUMN 120H OF THE  RESULTS TABLE
DROP TABLE IF EXISTS ISABELA.DATA_120H;
SELECT *,
CASE 
	WHEN CHARTTIME_OF_AKI > INTIME + INTERVAL '120 HOUR' 
	 AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '120 HOUR' + INTERVAL  '168 HOUR'
		THEN 1 
	ELSE 0 
END as AKI_7DAYS
INTO ISABELA.DATA_120H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '120 HOUR' 
	AND (CHARTTIME_OF_AKI > INTIME + INTERVAL '120 hour' OR CHARTTIME_OF_AKI ISNULL);
--1910


--CREATE TABLE FOR COLUMN 144H OF THE  RESULTS TABLE
DROP TABLE IF EXISTS ISABELA.DATA_144H;
SELECT *,
CASE 
	WHEN CHARTTIME_OF_AKI > INTIME + INTERVAL '144 HOUR' 
	 AND CHARTTIME_OF_AKI <= INTIME + INTERVAL '144 HOUR' + INTERVAL  '168 HOUR'
		THEN 1 
	ELSE 0 
END as AKI_7DAYS
INTO ISABELA.DATA_144H
FROM ISABELA.ICUSTAYS_PAT_FLAG
WHERE OUTTIME-INTIME >= INTERVAL '144 HOUR' 
	AND (CHARTTIME_OF_AKI > INTIME + INTERVAL '144 hour' OR CHARTTIME_OF_AKI ISNULL);
--1346

 
 ---------------------------------------------------------------------------------------
 
