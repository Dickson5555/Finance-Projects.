CREATE DATABASE Customer_Profitability;

/* What is each customers total revenue,total cost
gross profit and gross margin */
SELECT
  c.customer_id,
  c.customer_name,
  c.region,
  c.industry,
   SUM(t.total_revenue) AS total_revenue,
   SUM(t.total_cost) AS total_cost,
   SUM(t.total_revenue) - SUM(t.total_cost) AS gross_profit,
   CASE WHEN SUM(t.total_revenue) = 0 THEN 0 
   ELSE ROUND((SUM(t.total_revenue) - SUM(t.total_cost))/
   SUM(t.total_revenue) *100,2)
		END AS gross_margin_pct
        FROM customers c
        JOIN transactions t USING(customer_id)
        GROUP BY c.customer_id,c.customer_name,c.region,
        c.industry
        ORDER BY gross_profit DESC
        LIMIT 100;
        
        
/*What is the total support cost per customer*/
SELECT
   customer_id,
    SUM(support_cost) AS total_support_cost
    FROM customer_support_costs
     GROUP BY customer_id;
     
     /*Customer Profitability Segment*/
     WITH cust_fin AS (
     SELECT
      c.customer_id,
      c.customer_name,
      COALESCE(SUM(t.total_revenue),0) AS total_revenue,
      COALESCE (SUM(t.total_cost),0) AS total_cost,
      COALESCE(s.total_support_cost,0) AS total_support_cost,
      c.cac_usd
       FROM customers c 
       LEFT JOIN transactions t ON c.customer_id = t.customer_id
       LEFT JOIN (
       SELECT customer_id,SUM(support_cost) AS total_support_cost
       FROM customer_support_costs
       GROUP BY customer_id)
        s ON c.customer_id = s.customer_id
        GROUP BY c.customer_id,c.customer_name,
        s.total_support_cost,c.cac_usd)
        SELECT
         customer_id,customer_name,total_revenue,total_cost,
         total_support_cost,cac_usd,
         (total_revenue - total_cost - total_support_cost - cac_usd)
         AS net_profit,
         CASE 
         WHEN (total_revenue - total_cost - total_support_cost - cac_usd)
          >= 1000 THEN "HIGH"
          WHEN (total_revenue - total_cost - total_support_cost - cac_usd)
          BETWEEN 200 AND 999 THEN "Moderate"
          WHEN (total_revenue - total_cost - total_support_cost - cac_usd)
          BETWEEN 0 AND 199 THEN "Low"
          ELSE "Unprofitable"
          END AS Profit_segment
          FROM cust_fin
          ORDER BY net_profit DESC;
       
       
       /*Top 10 customers by Lifetime value*/
WITH per_customer AS(
       SELECT 
         c.customer_id,
         c.customer_name,
          COALESCE(SUM(t.total_revenue),0) AS total_revenue,
          COALESCE(SUM(t.total_cost),0) AS total_cost,
          COALESCE(s.total_support_cost,0) AS total_support_cost
          FROM customers c 
          LEFT JOIN transactions t ON c.customer_id = t.customer_id
          LEFT JOIN (
          SELECT customer_id, SUM(support_cost) AS total_support_cost
          FROM customer_support_costs
          GROUP BY customer_id )
         s ON c.customer_id  = s.customer_id
          GROUP BY c.customer_id,c.customer_name,s.total_support_cost)
          SELECT
           customer_id,
           customer_name,
           (total_revenue - total_cost - total_support_cost) AS historical_clv 
           FROM per_customer
           ORDER BY historical_clv DESC
           LIMIT 10;   
           
           /*CLV with rentention and margin assumptions*/
           SELECT
              customer_id,
              avg(total_revenue - total_cost) AS 
              avg_margin_per_tx,
              COUNT(*)/
              (DATEDIFF(MAX(transaction_date),
              MIN(transaction_date)) / 365.0 + 0.001) AS 
              tx_per_year
              FROM transactions
              GROUP BY customer_id;
              
              
              /*CAC Ratio and Payback*/
              WITH clv AS (
              SELECT c.customer_id,
              COALESCE(SUM(t.total_revenue) - SUM(t.total_cost) -
              COALESCE(s.total_support_cost,0),0) AS historical_clv,
              c.cac_usd
              FROM customers c 
              LEFT JOIN transactions t ON c.customer_id = t.customer_id
              LEFT JOIN (SELECT customer_id,
              SUM(support_cost) AS total_support_cost
              FROM customer_support_costs GROUP BY customer_id) 
              s ON c.customer_id = s.customer_id
              GROUP BY c.customer_id,c.cac_usd,s.total_support_cost)
              SELECT
              customer_id,historical_clv,cac_usd,
              CASE 
              WHEN cac_usd = 0 THEN NULL ELSE 
              ROUND(historical_clv / cac_usd,2) END AS 
              clv_cac_ratio,
              CASE WHEN cac_usd = 0 THEN "No CAC"
              WHEN historical_clv / cac_usd >= 3
              THEN "Excellent"
              WHEN historical_clv / cac_usd
              BETWEEN 1 AND 3 THEN "OK"
              WHEN historical_clv / cac_usd
              BETWEEN 0 AND 1 THEN "Poor"
              ELSE "Negative"
              END AS Ratio_Segment
              FROM clv
              ORDER BY clv_cac_ratio DESC;
              
              /*Profitability by Region*/
              SELECT
               c.region,c.industry,
               SUM(total_revenue) AS revenue,
               SUM(total_cost) AS cost,
               SUM(total_revenue) - SUM(total_cost) AS gross_profit,
               CASE WHEN SUM(total_revenue) = 0 THEN 0
               ELSE
               ROUND((SUM(total_revenue) - SUM(total_cost))/
               SUM(total_revenue) * 100,2) END AS gross_margin_pct
               FROM transactions t
               JOIN customers c ON t.customer_id = c.customer_id
               GROUP BY c.region,c.industry
               ORDER BY gross_profit DESC;
               
               
               /*Cohort,retention view (Acquisition month cohorts)*/
               WITH first_tx AS (
               SELECT customer_id,
               DATE_FORMAT(acquisition_date,"%Y-%m") AS cohort_month
               FROM customers),
               tx_months AS (
               SELECT customer_id,
               DATE_FORMAT(transaction_date,"%Y-%m") AS 
               tx_month 
               FROM transactions)
               SELECT 
               f.cohort_month,tm.tx_month,
               COUNT(DISTINCT tm.customer_id) AS active_customers
               FROM first_tx f 
               JOIN tx_months tm ON f.customer_id = tm.customer_id
               GROUP BY f.cohort_month,tm.tx_month
               ORDER BY f.cohort_month,tm.tx_month;
               
               
               /*Unprofitable Products(Low margin or negative margin*/
               SELECT 
               p.product_id,p.product_name,p.category,
               p.unit_cost,p.unit_price,t.total_cost,
               t.product_id,
               ROUND((p.unit_price - p.unit_cost) / 
               p.unit_price * 100,2) AS unit_margin_pct,
               SUM(t.quantity) AS  qty_sold,
               SUM(t.total_revenue) AS revenue 
               FROM products p 
               LEFT JOIN transactions t ON p.product_id = t.product_id
               GROUP BY p.product_id,p.product_name,p.unit_cost,
               p.category,p.unit_price,t.total_cost
               HAVING 
               ROUND((p.unit_price - p.unit_cost) / 
               p.unit_price * 100,2) < 50 OR 
               SUM(t.total_revenue) < 0.9 * (SUM(t.total_cost))
               ORDER BY unit_margin_pct ASC;               
               
               
               /*Time Series,monthly revenue,cost ,profits*/
               SELECT
               DATE_FORMAT(transaction_date,"%Y-%m") AS month,
               SUM(floor(total_revenue)) AS revenue,
               SUM(floor(total_cost)) AS cost,
              floor(SUM(total_revenue) - SUM(total_cost)) AS gross_profit
               FROM transactions
               GROUP BY month 
               ORDER BY month ;
               