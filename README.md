# Soda Manufacturing Line Productivity Analysis

##  Overview

This project involves cleaning and analysing production batch data from a beverage  bottling line. The dataset tracks batch runs across multiple product lines (Cola, Lemon 
Lime, Orange, Root Beer, Diet Cola), capturing operator shifts, downtime causes, and production timing to support process improvement decisions.

### Business Problem

The plant supervisor wants to know why the production line isn't hitting its productivity target, which downtime factors are costing the most time, and whether the issue is equipment, process, or operator-driven - so they know where to intervene first.

#### Dashboard

![Screenshot of dashboard](Images/Dashboard.png)

#### Tools & Tech Stack

SQL Server, T-SQL, Power BI, DAX and Power Query

#### Data Model

The model follows a star schema: LineProductivity (batch-level fact table) sits at the centre, related to Products and a calculated Date table as dimensions, with vw_LineDowntimeUnpivoted as a second fact table (one row per batch per downtime factor) relating to DowntimeFactors as a dimension.

![Screenshot of model view](Images/Model-view.png)

Downtime was originally stored as a wide table (one column per factor, F1–F12). This was unpivoted in SQL into a long/tall fact table so Power BI could filter and aggregate downtime flexibly by factor, operator error, day, or product - a wide format would have made this analysis impractical.

#### Findings

1. The line isn't slow; it is stopping. i.e., performance sits at 100%, meaning when the line is running, it runs at full speed, but availability sits at 64.02%, same with efficiency. Which means the entire productivity gap is due to downtime. So, every point of efficiency recovered has to come from reducing stoppages.
2. Both equipment, process and operator behaviour need attention. Operator error downtime accounts for 52.4% of the total downtime, and equipment/process account for 47.6%. These numbers are close; hence, the intervention plan needs two-track running in parallel.
3. Three factors account for 58% of all downtime, which are
   * Machine adjustment - 332 mins (operator error)
   * Machine Failure - 254 mins (equipment process)
   * Inventory shortage - 225 mins (process chain)
   This accounts for 811 of 1388 mins of total downtime; hence, fixing them will have a great impact on the line productivity.
4. Downtime clusters hard on Monday (503) and Friday (444), and this accounts for 68% of the week's total downtime. Monday spikes often point to equipment sitting idle over the weekend and failing on restart, or to missing the start-up checklist; Friday spikes often point to fatigued, rushed changeover or end-of-the-week short-staffing. Hence, these 2 days need investigation
5. Operator downtime is evenly distributed. No single operator is disproportionately bad.
6. Cola shows the highest total downtime, but that reflects volume; Cola's raw total is inflated by running far more batches than other flavours, but its per-batch rate confirms it's still a genuine problem as it's the second-worst on a per-batch basis.
   * batches run = total downtime/downtime per batch
7. Orange ran only one batch, so its per-batch figure is not an average. It's one data point, so it needs direct investigation before any policy change.

#### Recommendation

1. Shift preventive maintenance scheduling to target Monday and Friday, as this addresses 68% of weekly downtime
2. Standardise the machine adjustment procedure and service the machine before usage, as the 2 account for 42.2% of total downtime
3. Review inventory staging/reorder points with the supply chain team; this is the one major factor that's neither equipment nor operator, and no amount of training or machine fixes will touch it.
4. The 4 operators should be retrained properly or employ the best hands.
