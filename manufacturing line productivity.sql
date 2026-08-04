
/*
	Business Problem
	The plant supervisor wants to know why the production line isn't hitting its productivity target, which downtime factors are 
	costing the most time, and whether the issue is equipment, process, or operator-driven - so they know where to intervene first.
*/


IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ManufacturingLineProductivity')
BEGIN
    CREATE DATABASE ManufacturingLineProductivity;
END

GO
USE ManufacturingLineProductivity;
GO



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

-- This calculate the total ideal time for all the batches. i.e which is also the total runtime.


SELECT SUM(p.Min_batch_time) AS TotalIdealTime
FROM LineProductivity AS lp
JOIN Products AS p 
ON lp.Product = p.Product;

-- Performance % 

SELECT 
    CAST(
        (SELECT SUM(p.Min_batch_time) 
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

downtime minutes as percentage of runtime means of the time the line was actually running, what fraction was lost to downtime?
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


/*
1. Which downtime factors account for the most lost production time, and what's the estimated output gain if the top 2 were eliminated?

*/

SELECT * FROM vw_LineDowntimeUnpivoted;
SELECT * FROM vw_DowntimeWithReasons;

-- Downtime Factor that account for the most lost production time

SELECT ldu.DowntimeFactor, SUM(ldu.DowntimeMinutes) AS lost_Production_Time, ldr.Description, ldr.Operator_Error
FROM vw_LineDowntimeUnpivoted AS ldu
INNER JOIN (
    SELECT DISTINCT DowntimeFactor, Description, Operator_Error
    FROM vw_DowntimeWithReasons
) AS ldr
ON ldu.DowntimeFactor = ldr.DowntimeFactor
GROUP BY ldu.DowntimeFactor, ldr.Description, ldr.Operator_Error
ORDER BY lost_Production_Time DESC;

-- factor 6 and 7 account for it the most

-- how many estimated batches gained. where: Estimated_Batches_Gained = Top2_DowntimeMinutes / Avg_Min_Batch_Time

SELECT
    (SELECT SUM(DowntimeMinutes) FROM vw_LineDowntimeUnpivoted 
     WHERE DowntimeFactor IN ('F6', 'F7'))  -- top 2 factors downtime
    / (SELECT AVG(Min_batch_time) FROM Products)
    AS Estimated_Batches_Gained;

-- There will be 8 additional batches that will be gained.


/*
2. Which operator has the most downtime?
*/

SELECT lp.Operator, SUM(ldu.DowntimeMinutes) AS DowntimeMinutes FROM LineProductivity AS lp
INNER JOIN vw_LineDowntimeUnpivoted AS ldu
ON lp.Batch = ldu.Batch
GROUP BY lp.Operator
ORDER BY DowntimeMinutes DESC;

-- Charlie has the most downtime 

/*
 3. How far is the line running below its productivity target, and how much of that gap is downtime vs. slow running once active?
*/

-- The answer to this question is an explanation. Because the solving is already done on availability and efficiency in the KPI

/*
Here is the answer

Downtime accounts for 36.98% of the gap. This is the Availability loss (100% − 64.02%). = 35.98

Slow running accounts for 0%. Performance is at 100%, meaning there's no evidence in this dataset of the line running below its 
target speed while active.

Meaning the line is running 35.98% below its 100% productivity target

*/

/*
4. Does downtime or efficiency vary meaningfully by product/flavor?
*/

-- Actual runtime including the batch and product because of the number 4 question

CREATE VIEW vw_ActualRunTimeByBatch AS
SELECT
    Batch,
    Product,
    Date,
    CASE
        WHEN DATEDIFF(MINUTE, Start_Time, End_Time) < 0 THEN DATEDIFF(MINUTE, Start_Time, End_Time) + 1440
        ELSE DATEDIFF(MINUTE, Start_Time, End_Time)
    END AS ActualRunTime
FROM LineProductivity;

SELECT * FROM vw_ActualRunTimeByBatch;

-- answering the question

SELECT
    p.Product,
    p.Flavor,
    COUNT(lp.Batch) AS Batches,
    SUM(ab.ActualRunTime) AS TotalActualRunTime,
    SUM(dt.TotalBatchDowntime) AS TotalDowntime,
    CAST(SUM(dt.TotalBatchDowntime)  / COUNT(lp.Batch) AS DECIMAL(5,2)) AS AvgDowntimePerBatch,
    SUM(p.Min_batch_time) AS TotalMinBatchTime,
    CAST(
        (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
        / SUM(ab.ActualRunTime)
    AS DECIMAL(5,2)) AS Availability_Percent,
    CAST(
        SUM(p.Min_batch_time) * 100.0
        / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
    AS DECIMAL(5,2)) AS Performance_Percent,
    CAST(
        (
            (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
            / SUM(ab.ActualRunTime)
        )
        *
        (
            SUM(p.Min_batch_time) * 100.0
            / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
        )
        / 100
    AS DECIMAL(5,2)) AS Efficiency_Percent
FROM LineProductivity AS lp
JOIN Products AS p ON lp.Product = p.Product
JOIN vw_ActualRunTimeByBatch AS ab ON ab.Batch = lp.Batch
JOIN (
    SELECT Batch, SUM(DowntimeMinutes) AS TotalBatchDowntime
    FROM vw_LineDowntimeUnpivoted
    GROUP BY Batch
) AS dt ON dt.Batch = lp.Batch
GROUP BY p.Product, p.Flavor
ORDER BY Availability_Percent ASC;

-- Downtime varies meaningully by product


/*
5. Is downtime or efficiency trending up/down over time, and are there specific days/operators driving the trend?
*/

SELECT * FROM vw_LineDowntimeUnpivoted;

-- For Time trend


SELECT
    DATENAME(WEEKDAY, lp.Date) AS DayOfWeek,
    COUNT(lp.Batch) AS Batches,
    SUM(dt.TotalBatchDowntime) AS TotalDowntime,
    CAST(
        (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
        / SUM(ab.ActualRunTime)
    AS DECIMAL(5,2)) AS Availability_Percent,
    CAST(
        SUM(p.Min_batch_time) * 100.0
        / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
    AS DECIMAL(5,2)) AS Performance_Percent,
    CAST(
        (
            (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
            / SUM(ab.ActualRunTime)
        )
        *
        (
            SUM(p.Min_batch_time) * 100.0
            / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
        )
        / 100
    AS DECIMAL(5,2)) AS Efficiency_Percent
FROM LineProductivity AS lp
JOIN Products AS p ON lp.Product = p.Product
JOIN vw_ActualRunTimeByBatch AS ab ON ab.Batch = lp.Batch
LEFT JOIN (
    SELECT Batch, SUM(DowntimeMinutes) AS TotalBatchDowntime
    FROM vw_LineDowntimeUnpivoted
    GROUP BY Batch
) AS dt ON dt.Batch = lp.Batch
GROUP BY DATENAME(WEEKDAY, lp.Date)
ORDER BY SUM(dt.TotalBatchDowntime) DESC;

-- Monday and Friday has the highest downtime. BUT if we want a chronological ordering

SELECT
    DATENAME(WEEKDAY, lp.Date) AS DayOfWeek,
    COUNT(lp.Batch) AS Batches,
    SUM(dt.TotalBatchDowntime) AS TotalDowntime,
    CAST(
        (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
        / SUM(ab.ActualRunTime)
    AS DECIMAL(5,2)) AS Availability_Percent,
    CAST(
        SUM(p.Min_batch_time) * 100.0
        / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
    AS DECIMAL(5,2)) AS Performance_Percent,
    CAST(
        (
            (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
            / SUM(ab.ActualRunTime)
        )
        *
        (
            SUM(p.Min_batch_time) * 100.0
            / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
        )
        / 100
    AS DECIMAL(5,2)) AS Efficiency_Percent
FROM LineProductivity AS lp
JOIN Products AS p ON lp.Product = p.Product
JOIN vw_ActualRunTimeByBatch AS ab ON ab.Batch = lp.Batch
LEFT JOIN (
    SELECT Batch, SUM(DowntimeMinutes) AS TotalBatchDowntime
    FROM vw_LineDowntimeUnpivoted
    GROUP BY Batch
) AS dt ON dt.Batch = lp.Batch
GROUP BY DATENAME(WEEKDAY, lp.Date)
ORDER BY
    CASE DATENAME(WEEKDAY, lp.Date)
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        WHEN 'Sunday' THEN 7
    END;

-- Operator trend


SELECT
    lp.Operator,
    COUNT(lp.Batch) AS Batches,
    SUM(dt.TotalBatchDowntime) AS TotalDowntime,
    CAST(
        (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
        / SUM(ab.ActualRunTime)
    AS DECIMAL(5,2)) AS Availability_Percent,
    CAST(
        SUM(p.Min_batch_time) * 100.0
        / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
    AS DECIMAL(5,2)) AS Performance_Percent,
    CAST(
        (
            (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
            / SUM(ab.ActualRunTime)
        )
        *
        (
            SUM(p.Min_batch_time) * 100.0
            / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
        )
        / 100
    AS DECIMAL(5,2)) AS Efficiency_Percent
FROM LineProductivity AS lp
JOIN Products AS p ON lp.Product = p.Product
JOIN vw_ActualRunTimeByBatch AS ab ON ab.Batch = lp.Batch
LEFT JOIN (
    SELECT Batch, SUM(DowntimeMinutes) AS TotalBatchDowntime
    FROM vw_LineDowntimeUnpivoted
    GROUP BY Batch
) AS dt ON dt.Batch = lp.Batch
GROUP BY lp.Operator
ORDER BY TotalDowntime DESC;

-- Charlie and Dee has the most downtime


-- Combined: Day of Week + Operator trend

SELECT
    DATENAME(WEEKDAY, lp.Date) AS DayOfWeek,
    lp.Operator,
    COUNT(lp.Batch) AS Batches,
    SUM(dt.TotalBatchDowntime) AS TotalDowntime,
    CAST(
        (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
        / SUM(ab.ActualRunTime)
    AS DECIMAL(5,2)) AS Availability_Percent,
    CAST(
        SUM(p.Min_batch_time) * 100.0
        / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
    AS DECIMAL(5,2)) AS Performance_Percent,
    CAST(
        (
            (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime)) * 100.0
            / SUM(ab.ActualRunTime)
        )
        *
        (
            SUM(p.Min_batch_time) * 100.0
            / (SUM(ab.ActualRunTime) - SUM(dt.TotalBatchDowntime))
        )
        / 100
    AS DECIMAL(5,2)) AS Efficiency_Percent
FROM LineProductivity AS lp
JOIN Products AS p ON lp.Product = p.Product
JOIN vw_ActualRunTimeByBatch AS ab ON ab.Batch = lp.Batch
LEFT JOIN (
    SELECT Batch, SUM(DowntimeMinutes) AS TotalBatchDowntime
    FROM vw_LineDowntimeUnpivoted
    GROUP BY Batch
) AS dt ON dt.Batch = lp.Batch
GROUP BY DATENAME(WEEKDAY, lp.Date), lp.Operator
ORDER BY
    CASE DATENAME(WEEKDAY, lp.Date)
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        WHEN 'Sunday' THEN 7
    END,
    TotalDowntime DESC;
    
-- Monday had the highest downtime with Charlie at its operator
