
/*
	Business Problem
	The plant supervisor wants to know why the production line isn't hitting its productivity target, which downtime factors are 
	costing the most time, and whether the issue is equipment, process, or operator-driven - so they know where to intervene first.
*/


-- This removes the sql server default precision for the time datatype
ALTER TABLE LineProductivity
ALTER COLUMN Start_Time TIME(0);

ALTER TABLE LineProductivity
ALTER COLUMN End_Time TIME(0);

-- unpivoting the DowntimeFactors table, so as to peform analyis on them easily.

SELECT 
	Batch,
	DowntimeFactor,
	DowntimeMinutes
FROM (
	SELECT Batch, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12
	FROM LineDowntimeWide
	) AS src
UNPIVOT(
	DowntimeMinutes FOR DowntimeFactor IN (F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12)
	) AS unpvt;

-- saving our unpivoted as view so we can query it easily.



CREATE VIEW vw_LineDowntimeUnpivoted AS
SELECT 
	Batch,
	DowntimeFactor,
	DowntimeMinutes
FROM(
	SELECT Batch, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12
	FROM LineDowntimeWide
	) AS src
UNPIVOT(
	DowntimeMinutes FOR DowntimeFactor IN (F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12)
	) AS unpvt;


SELECT * FROM vw_LineDowntimeUnpivoted;


-- joining the linedowntimeunpivoted to the downtimefactors to bring out the description and operator error flag for each batch

SELECT
    ldu.Batch,
    ldu.DowntimeFactor,
    df.Description,
    df.Operator_Error,
    ldu.DowntimeMinutes
FROM vw_LineDowntimeUnpivoted AS ldu
JOIN DowntimeFactors AS df
    ON CAST(SUBSTRING(ldu.DowntimeFactor, 2, LEN(ldu.DowntimeFactor) - 1) AS INT) = df.Factor


-- The View was created for easy referencing when analysing.

CREATE VIEW vw_DowntimeWithReasons AS
SELECT
    ldu.Batch,
    ldu.DowntimeFactor,
    df.Description,
    df.Operator_Error,
    ldu.DowntimeMinutes
FROM vw_LineDowntimeUnpivoted AS ldu
JOIN DowntimeFactors AS df
    ON CAST(SUBSTRING(ldu.DowntimeFactor, 2, LEN(ldu.DowntimeFactor) - 1) AS INT) = df.Factor

SELECT * FROM vw_DowntimeWithReasons;


-- KPI REQUIREMENT


/* 

1. Availability %: This answers how much a schedule time was actually spent running vs stopped.

Scheduled time is normally the time the line was planned to be running e.g., an 10-hour shift, minus any planned breaks or 
maintenance windows

The formular is Availability% = runtime / actual runtime
where actual runtime =  End_Time - Start_Time
And runtime = actual runtime - downtime

*/


-- Actual runtime


SELECT
    CASE
        WHEN DATEDIFF(MINUTE, Start_Time, End_Time) < 0 THEN DATEDIFF(MINUTE, Start_Time, End_Time) + 1440
        ELSE DATEDIFF(MINUTE, Start_Time, End_Time)
    END AS ActualRunTime
FROM LineProductivity;


CREATE VIEW vw_ActualRunTime AS
SELECT
    CASE
        WHEN DATEDIFF(MINUTE, Start_Time, End_Time) < 0 THEN DATEDIFF(MINUTE, Start_Time, End_Time) + 1440
        ELSE DATEDIFF(MINUTE, Start_Time, End_Time)
    END AS ActualRunTime
FROM LineProductivity;

SELECT * FROM vw_ActualRunTime

-- TOTAL runtime. Finding the runtime of all the batches.

SELECT SUM(ActualRunTime) AS actual_runtime FROM vw_ActualRunTime

-- total downtime. Finding the downtime of all the batches.

SELECT SUM(DowntimeMinutes) AS total_downtime FROM vw_LineDowntimeUnpivoted

-- To get the runtime

SELECT
 (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime) 
        - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted) AS Runtime;

-- putting all our variable together since we have a value for all of them.

SELECT 
    (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime) AS ActualRunTime,
    (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted) AS TotalDowntime,
    (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime) 
        - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted) AS Runtime;

-- Availability%

SELECT
    CAST(
    (
        (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
        - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
    )
    * 100.0
    / (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime) AS DECIMAL(4,2)) AS Availability_percentage;

-- This means about 64% of the total scheduled run time was actually productive, and the remaining 36% was lost to downtime


/*
2. Performance %: This answers when the line was running, was it running at the speed it ought to run.

The formular for this is

Min batch time ÷ Runtime

Min batch time is the time a batch can run without zero time which we can alo refer to as our runtime. and from our availability 
calculation. the runtime is 2470

*/

-- This calculate the total ideal time for all the batches.


SELECT SUM(p.Min_batch_time) AS TotalIdealTime
FROM LineProductivity AS lp
JOIN Products AS p 
ON lp.Product = p.Product;

-- Performance % 

SELECT 
    CAST(
        (SELECT SUM(p.[Min_batch_time]) 
         FROM LineProductivity AS lp
         JOIN Products AS p ON lp.Product = p.Product) * 100.0
        / (
            (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
                - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
        )
    AS DECIMAL(5,2)) AS Performance_Percent;

-- The line was running at the exact speed it ought to run when it was running hence 100%

-- OR we can say (runtime/runtime) * 100

SELECT
(
    (
        (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
        -
        (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
    ) * 100
)
/
(
    (
        (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
        -
        (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
    )
) AS Performance_Percentage;



/*
3. Efficiency % : This answers if the line is hitting its productivity target over time

forumalar: Availability × Performance

*/

SELECT
    
    CAST(
    (
        (
          (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
         - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
        )
    * 100.0
    / (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
    )

    *

    (
        (SELECT SUM(p.[Min_batch_time]) 
         FROM LineProductivity AS lp
         JOIN Products AS p ON lp.Product = p.Product) * 100.0
        / (
            (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime)
                - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
            )
        )
        / 100
        AS DECIMAL (5,2)) Efficiency_Percent;

-- The line is not hitting its productivity target as it has an efficiency percent of 64.02 and this is due to its downtime


/*
4. Total downtime minutes (and downtime minutes as percentage of runtime) 

Total downtime minutes measure the total time lost  during the batch during the total scheduled time

downtime minutes as percentage of runtime measures how much time was lost to downtime, expressed as a percentage of the time the 
line actually spent running productively (Runtime), not as a percentage of total scheduled time.

Of the time the line was actually running, what fraction was lost to downtime?
*/

-- Total downtime minutes

SELECT SUM(DowntimeMinutes) AS total_downtime FROM vw_LineDowntimeUnpivoted

-- downtime minutes as percentage of runtime

SELECT
    CAST(
      (SELECT SUM(DowntimeMinutes) AS total_downtime FROM vw_LineDowntimeUnpivoted) * 100
    
    /
      (
        (SELECT SUM(ActualRunTime) FROM vw_ActualRunTime) 
            - (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted)
      )
      AS DECIMAL (5,2)) AS DowntimePercentOfRuntime;

-- for every time the line was running it lost 56% of the time to downtime. and this is used for comparison


-- BUSINESS QUESTIONS