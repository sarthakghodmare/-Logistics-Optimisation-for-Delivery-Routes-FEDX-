select * from fedex_delivery_agents;

select * from fedex_orders;

select * from fedex_routes;
select * from fedex_shipments;
select * from fedex_warehouses;


-- Task 1: Data Cleaning & Preparation

-- Identify and delete duplicate Order_ID or Shipment_ID records. 

select Shipment_ID,count(*) as count
from fedex_shipments
group by Shipment_ID
having count(*) >1;

select Order_ID,count(*) as count
from fedex_orders
group by Order_ID
having count(*) >1;

-- Replace null or missing Delay_Hours values in the Shipments Table with the average
-- delay for that Route_ID.



-- Show missing Delay_Hours with Route average
SELECT s.Shipment_ID,
       s.Route_ID,
       s.Delay_Hours,
       r.avg_delay
FROM fedex_shipments s
INNER JOIN (
    SELECT Route_ID,
           AVG(Delay_Hours) AS avg_delay
    FROM fedex_shipments
    WHERE Delay_Hours IS NOT NULL
    GROUP BY Route_ID
) r
ON s.Route_ID = r.Route_ID
WHERE s.Delay_Hours IS NULL;

UPDATE fedex_shipments s
JOIN (
    SELECT Route_ID,
           AVG(Delay_Hours) AS avg_delay
    FROM fedex_shipments
    WHERE Delay_Hours IS NOT NULL
    GROUP BY Route_ID
) r
ON s.Route_ID = r.Route_ID
SET s.Delay_Hours = r.avg_delay
WHERE s.Delay_Hours IS NULL;

SELECT COUNT(*) AS remaining_nulls
FROM fedex_shipments
WHERE Delay_Hours IS NULL;



-- Convert all date columns (Order_Date, Pickup_Date, Delivery_Date) into YYYY-MM-DD
 -- HH:MM:SS format using SQL date functions.
 
select * from fedex_shipments;

ALTER TABLE fedex_shipments
MODIFY COLUMN Pickup_Date DATETIME,
MODIFY COLUMN Delivery_Date DATETIME;

 
select * from fedex_orders;

ALTER TABLE fedex_orders MODIFY COLUMN Order_Date DATETIME;

-- Ensure that no Delivery_Date occurs before Pickup_Date (flag such records).

select Shipment_ID, Pickup_Date,Delivery_Date from fedex_shipments
where Delivery_Date < Pickup_Date;	


-- Validate referential integrity between Orders, Routes, Warehouses, and Shipments.

select o.* 
from fedex_orders o
left join fedex_warehouses w
on o.Warehouse_ID=w.Warehouse_ID
where w.Warehouse_ID is null; 
 #A LEFT JOIN returns all child records + matched parent records
#If parent is NULL, it means the child has no valid parent

select s.*
from fedex_shipments s
left join fedex_warehouses w
on s.Warehouse_ID=w.Warehouse_ID
where w.Warehouse_ID is null; 

select s.* 
from fedex_shipments s
left join fedex_delivery_agents a
on s.Agent_ID=a.Agent_ID
where a.Agent_ID is null;

select s.* 
from fedex_shipments s
left join fedex_routes r
on s.Route_ID=r.Route_ID
where r.Route_ID is null;

select s.*
from fedex_shipments s
left join fedex_orders o
on s.Order_ID=o.Order_ID
where o.Order_ID is null;

-- Task 2: Delivery Delay Analysis 
# Delivery delay (in hours) for each shipment
# (Using Delivery_Date – Pickup_Date)

select 
Shipment_ID,Pickup_Date,Delivery_Date,
TIMESTAMPDIFF (HOUR, Pickup_Date,Delivery_Date) as Delivery_Delay_Hours
from fedex_shipments;

-- Find the Top 10 delayed routes based on average delay hours.

select  s.Route_ID,r.Source_City,r.Source_Country,r.Destination_City,r.Destination_Country,
	round(avg(s.Delay_Hours),2) as avg_delay_hours,
	count(*) as  shipment_count
from fedex_shipments s
inner join fedex_routes r
on s.Route_ID=r.Route_ID
group by s.Route_ID,r.Source_City,r.Source_Country,r.Destination_City,r.Destination_Country
order by avg_delay_hours desc
limit 10
;

-- Use SQL window functions to rank shipments by delay within each Warehouse_ID.

select Shipment_ID , Order_ID,Warehouse_Id,Delay_Hours,
dense_rank () over (partition by Warehouse_ID order by Delay_Hours desc) 
as Delay_rank_in_warehouse
from fedex_shipments;


-- Identify the average delay per Delivery_Type (Express / Standard) to compare
-- service-level efficiency.

select o.Delivery_Type,
	round(avg(s.Delay_Hours),2) as Avg_delay_Hours,
	count(*) as Shipment_count
from fedex_orders o
inner join fedex_shipments s
on o.Order_ID=s.Order_ID	
group by o.Delivery_Type
order by Avg_delay_Hours desc;

-- Task 3: Route Optimization Insights

-- 	for each route: Average transit time (in hours) across all shipments.

SELECT 
    s.Route_ID,
    r.Source_City,
    r.Source_Country,
    r.Destination_City,
    r.Destination_Country, 
    r.Avg_Transit_Time_Hours AS avg_transit_time_hours,
    COUNT(*) AS shipment_count
FROM fedex_shipments s
INNER JOIN fedex_routes r
ON s.Route_ID = r.Route_ID
GROUP BY   s.Route_ID, r.Source_City,   r.Source_Country,r.Destination_City, r.Destination_Country,r.Avg_Transit_Time_Hours
ORDER BY avg_transit_time_hours DESC;


-- Average delay (in hours) per route.

select Route_ID,
round(avg(Delay_Hours),2) as Avg_delay_in_hours
from fedex_shipments
group by Route_ID	
order by Avg_delay_in_hours desc;

-- Distance-to-time efficiency ratio = Distance_KM / Avg_Transit_Time_Hours
SELECT 
    r.Route_ID,
    r.Source_City,
    r.Destination_City,
    r.Avg_Transit_Time_Hours,
    (r.Distance_KM / r.Avg_Transit_Time_Hours) AS efficiency_ratio,
    COUNT(s.Shipment_ID) AS shipment_count
FROM fedex_routes r
LEFT JOIN fedex_shipments s
ON r.Route_ID = s.Route_ID
GROUP BY r.Route_ID, r.Source_City, r.Destination_City,r.Avg_Transit_Time_Hours,r.Distance_KM
ORDER BY efficiency_ratio DESC;

-- Find routes with >20% of shipments delayed beyond expected transit time.

select Route_ID,
count(*) as shipment_count,
sum(case when Delay_Hours >0 Then 1 else 0 End) as Delayed_shipments,
(sum(case when Delay_Hours >0 Then 1 else 0 End) /count(*)) * 100 as Delay_Percentage
from fedex_shipments 
group by Route_ID
HAVING Delay_Percentage > 20;

-- Identify 3 routes with the worst efficiency ratio (lowest distance-to-time).


SELECT 
    r.Route_ID,
    r.Source_City,
    r.Destination_City,
    r.Distance_KM,
    r.Avg_Transit_Time_Hours,
    (r.Distance_KM / r.Avg_Transit_Time_Hours) AS efficiency_ratio,
    COUNT(s.Shipment_ID) AS shipment_count
FROM fedex_routes r
jOIN fedex_shipments s
ON r.Route_ID = s.Route_ID
GROUP BY r.Route_ID, r.Source_City, r.Destination_City,r.Avg_Transit_Time_Hours,r.Distance_KM
ORDER BY efficiency_ratio asc
limit 3;

-- Task 4: Warehouse Performance

-- Find the top 3 warehouses with the highest average delay in shipments dispatched.

select s.Warehouse_ID,w.City,w.Country,avg(s.Delay_Hours) as avg_delay,
count(*) as Shipment_count
from fedex_shipments s
inner join fedex_warehouses w
on s.Warehouse_ID=w.Warehouse_ID
group by s.Warehouse_ID,w.City,w.Country
order by avg_delay desc
limit 3;


-- Calculate total shipments vs delayed shipments for each warehouse.

select s.Warehouse_ID,
count(*) as Total_shipments,
sum(case when s.Delay_Hours>0 then 1 else 0 end) as Delayed_shipments,
(sum(case when s.Delay_Hours>0 then 1 else 0 end)  /count(*)) * 100 as Delayed_Percentage
from fedex_shipments s
inner join fedex_warehouses w
on s.Warehouse_ID=w.Warehouse_ID
group by s.Warehouse_ID
order by Delayed_Percentage;

-- Use CTEs to identify warehouses where average delay exceeds the global average delay.

WITH Global_Avg AS (
    SELECT round(AVG(Delay_Hours),2) AS global_avg_delay -- Calculate global average delay across all shipments
    FROM fedex_shipments
),
Warehouse_Avg AS (
    SELECT Warehouse_ID, round(AVG(Delay_Hours),2) AS warehouse_avg_delay     -- Calculate average delay per warehouse
    FROM fedex_shipments
    GROUP BY Warehouse_ID
)
SELECT 
    w.Warehouse_ID,
    w.warehouse_avg_delay,
    g.global_avg_delay
FROM Warehouse_Avg w
CROSS JOIN Global_Avg g
WHERE w.warehouse_avg_delay > g.global_avg_delay
ORDER BY w.warehouse_avg_delay DESC;


-- Rank all warehouses based on on-time delivery percentage.

SELECT 
    Warehouse_ID,
    COUNT(*) AS total_shipments,
    SUM(CASE WHEN Delay_Hours <= 0 THEN 1 ELSE 0 END) AS on_time_shipments,
    (SUM(CASE WHEN Delay_Hours <= 0 THEN 1 ELSE 0 END) / COUNT(*)) * 100 AS on_time_delivery_percentage,
    RANK() OVER (ORDER BY (SUM(CASE WHEN Delay_Hours <= 0 THEN 1 ELSE 0 END) / COUNT(*)) DESC) AS rank_on_time
FROM fedex_shipments
GROUP BY Warehouse_ID
ORDER BY rank_on_time;

-- Task 5: Delivery Agent Performance

 -- Rank delivery agents (per route) by on-time delivery percentage.
 select s.Route_ID,s.Agent_ID,a.Agent_Name,
 count(*) as Total_Shipment ,
 sum(case when Delay_Hours <=0 then 1 else 0 end) as on_time_delivery ,
 (sum(case when Delay_Hours <=0 then 1 else 0 end) /count(*) ) * 100 as  on_time_delivery_Percentage,
 rank() over (partition by s.Route_ID order by (sum(case when Delay_Hours =0 then 1 else 0 end) /count(*) ) * 100 desc)
 as Rank_agent_per_route
 from fedex_shipments s
 inner join fedex_delivery_agents  a
 on s.Agent_ID=a.Agent_ID
 group by s.Route_ID,s.Agent_ID,a.Agent_Name;
 
 -- Find agents whose on-time % is below 85%.
 
 select s.Agent_ID,a.Agent_Name,
 count(*) as Total_Shipment ,
 sum(case when Delay_Hours =0 then 1 else 0 end) as on_time_delivery ,
 (sum(case when Delay_Hours =0 then 1 else 0 end) /count(*) ) * 100 as  on_time_delivery_Percentage
 from fedex_shipments s
 inner join fedex_delivery_agents  a
 on s.Agent_ID=a.Agent_ID
 group by s.Agent_ID,a.Agent_Name
 having on_time_delivery_Percentage <85
 order by on_time_delivery_Percentage desc
 ;
 
 -- Compare the average rating and experience (in years) of the top 5 vs bottom 5 agents using subqueries.
select 
	'Top 5 Agents ' as 	Agent_Group,
    round(avg(Avg_Rating),2) as Avg_rating,
    round(avg(Experience_Years),2) as Avg_Experience_years
from(
select a.Agent_ID,a.Agent_Name,a.Avg_Rating,a.Experience_Years,
	   (sum(case when s.Delay_Hours <=0 then 1 else 0 end) /count(*))* 100 as on_time_percentage
from fedex_shipments s
inner join fedex_delivery_agents a
       on s.Agent_ID=a.Agent_ID
group by  a.Agent_ID,a.Agent_Name,a.Avg_Rating,a.Experience_Years
order by on_time_percentage desc
limit 5
) as TOP_5_agents
union all
select 
	'Bottom 5 Agents ' as 	Agent_Group,
    round(avg(Avg_Rating),2) as Avg_rating,
    round(avg(Experience_Years),2) as Avg_Experience_years
    
from(
select a.Agent_ID,a.Agent_Name,a.Avg_Rating,a.Experience_Years,
	   (sum(case when s.Delay_Hours <=0 then 1 else 0 end) /count(*))* 100 as on_time_percentage
from fedex_shipments s
inner join fedex_delivery_agents a
       on s.Agent_ID=a.Agent_ID
group by  a.Agent_ID,a.Agent_Name,a.Avg_Rating,a.Experience_Years
order by on_time_percentage asc
limit 5
) as bottom_5_agents;




-- Task 6: Shipment Tracking Analytics

-- For each shipment, display the latest status (Delivered, In Transit, or Returned) along
 -- with the latest Delivery_Date.
 
 select s.Shipment_ID, s.Delivery_Status,s.Delivery_Date
 from fedex_shipments s 
 inner join 
 ( select Shipment_ID,max(Delivery_Date) as Latest_delivery_date
 from fedex_shipments
 group by Shipment_ID) 
 latest
 on s.Shipment_ID=latest.Shipment_ID
 and s.Delivery_Date=latest.Latest_delivery_date;
 

-- Identify routes where the majority of shipments are still “In Transit” or “Returned”.
select Route_ID,
count(*) as Total_shipment,
sum(case when Delivery_Status In ('In Transit', 'Returned') then 1 else 0 end ) as NotDelivered,
(sum(case when Delivery_Status In ('In Transit', 'Returned') then 1 else 0 end ) /count(*) ) *100  as NotDelivered_Percentage
from fedex_shipments
group by Route_ID
order by NotDelivered_Percentage desc;


-- Find the most frequent delay reasons (if available in delay-related columns or flags).

select Delay_Reason, count(*) as occurence
 from fedex_shipments
 group by Delay_Reason
 order by occurence desc;
 
 -- Identify orders with exceptionally high delay (>120 hours) to investigate potential bottlenecks.
 
 select Shipment_ID,Order_ID ,Delivery_Date,Delivery_Status,Delay_Hours 
 from fedex_shipments
 where Delay_Hours >120
 order by Delay_Hours desc ;
 
 -- 	Task 7: Advanced KPI Reporting
  
-- Average Delivery Delay per Source_Country.

select  r.Source_Country,
count(*) as total_shipment,
round(avg(Delay_Hours),2)  as Avg_Delivery_Delay_Hours
from fedex_shipments s
inner join fedex_routes r
on s.Route_ID=r.Route_ID
group by r.Source_Country
order by Avg_Delivery_Delay_Hours desc;

-- On-Time Delivery % = (Total On-Time Deliveries / Total Deliveries) * 100.

select r.Route_ID,r.Source_Country,
count(*) as Total_Deliveries,
sum(case when s.Delay_Hours <=0 then 1 else 0 end) as On_time_Deliveries,
(sum(case when s.Delay_Hours <=0 then 1 else 0 end) /count(*))*  100 as  On_time_Deliveries_Percentage
from fedex_shipments s
inner join fedex_routes r
on s.Route_ID=r.Route_ID
group by r.Route_ID,r.Source_Country
order by On_time_Deliveries_Percentage desc;

-- Average Delay (in hours) per Route_ID. 
select Route_ID,
count(*) as Total_Shipment,
round(Avg(Delay_Hours),2) as avg_delay_hours
from fedex_shipments
group by Route_ID
order by avg_delay_hours desc;

-- Warehouse Utilization % = (Shipments_Handled / Capacity_per_day) * 100.
Create TAble warehouse_utilization
( Warehouse_ID varchar(20),
avg_utilization_Perentage DECIMAL(12,6)	
);

insert into  warehouse_utilization
with Daily_Utility  as (
select w.Warehouse_ID,
date(s.Pickup_Date ) as shiping_date,
count(*) as Shipments_Handled,
(count(*) / w.Capacity_per_day) *100 as Warehouse_Utilization_Percentage
from fedex_shipments s
inner join fedex_warehouses w
on s.Warehouse_ID=w.Warehouse_ID
group by w.Warehouse_ID,date(s.Pickup_Date),w.Capacity_per_day
)
select  Warehouse_ID,
round(avg(Warehouse_Utilization_Percentage) ,2) as Avg_Warehouse_Utilization_Percentage
from  Daily_Utility
group by Warehouse_ID;

SELECT *
FROM warehouse_utilization
order by avg_utilization_Perentage desc;

