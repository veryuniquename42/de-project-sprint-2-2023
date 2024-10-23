WITH
dwh_delta AS (-- +
    SELECT     
            dcs.customer_id AS customer_id,
            dcs.customer_name AS customer_name,
            dcs.customer_address AS customer_address,
            dcs.customer_birthday AS customer_birthday,
            dcs.customer_email AS customer_email,
            fo.order_id AS order_id,
            dp.product_id AS product_id,
            dp.product_price AS product_price,
            dp.product_type AS product_type,
            dc.craftsman_id AS craftsman_id,
            fo.order_completion_date - fo.order_created_date AS diff_order_date, 
            fo.order_status AS order_status,
            TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period,
            crd.customer_id AS exist_customer_id,
            dc.load_dttm AS craftsman_load_dttm,
            dcs.load_dttm AS customers_load_dttm,
            dp.load_dttm AS products_load_dttm
            FROM dwh.f_order fo 
                INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
                INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
                INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id 
                LEFT JOIN dwh.customer_report_datamart crd ON dcs.customer_id = crd.customer_id
                    WHERE (fo.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                            (dc.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                            (dcs.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                            (dp.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart))
),
dwh_update_delta AS (-- +
    SELECT     
            dd.exist_customer_id AS customer_id
            FROM dwh_delta dd 
                WHERE dd.exist_customer_id IS NOT NULL        
),
dwh_delta_insert_result AS (-- +
				SELECT  distinct
						T2.customer_id,
						T2.customer_name,
						T2.customer_address,
						T2.customer_birthday,
						T2.customer_email,
						T2.customer_money,
						T2.platform_money,
						T2.count_order,
						T2.avg_price_order,
						T2.median_time_order_completed,
						first_value(T3.product_type) over(partition by T2.customer_id order by T3.count_product desc) as top_product_category,
						first_value(T5.craftsman_id) over(partition by T2.customer_id order by T5.count_orders desc) as top_craftsman_id,
						T2.count_order_created,
						T2.count_order_in_progress,
						T2.count_order_delivery,
						T2.count_order_done,
						T2.count_order_not_done,
						T2.report_period
						
						FROM ( 
							SELECT
								T1.customer_id,
								T1.customer_name,
								T1.customer_address,
								T1.customer_birthday,
								T1.customer_email,
								SUM(T1.product_price) as customer_money,
								SUM(T1.product_price) * 0.1 as platform_money,
								count(T1.order_id) AS count_order,
								avg(T1.product_price) AS avg_price_order,
								percentile_cont(0.5) WITHIN GROUP(ORDER BY T1.diff_order_date) AS median_time_order_completed,
								sum(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created,
								sum(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END)AS count_order_in_progress,
								sum(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END)AS count_order_delivery,
								sum(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END)AS count_order_done,
								sum(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END)AS count_order_not_done,
								T1.report_period AS report_period
								FROM dwh.dwh_delta AS T1
									WHERE T1.exist_customer_id IS NULL
										GROUP BY T1.customer_id, T1.customer_name, T1.customer_address, T1.customer_birthday, T1.customer_email, T1.report_period
							) AS T2 
								INNER JOIN (
									SELECT
											dd.customer_id as customer_id_for_product_type,
											dd.product_type,
											COUNT(dd.product_id) AS count_product
											FROM dwh.dwh_delta AS dd
												GROUP BY dd.customer_id, dd.product_type
													ORDER BY count_product DESC) AS T3 ON T2.customer_id = T3.customer_id_for_product_type
								INNER JOIN (
									SELECT
											dd.customer_id as customer_id_for_top_craftsman,
											dd.craftsman_id,
											COUNT(dd.order_id) AS count_orders
											FROM dwh.dwh_delta AS dd
												GROUP BY dd.customer_id, dd.craftsman_id
													ORDER BY count_orders DESC) AS T5 ON T2.customer_id = T5.customer_id_for_top_craftsman
),
dwh_delta_update_result AS ( -- +
				SELECT  distinct
						T2.customer_id,
						T2.customer_name,
						T2.customer_address,
						T2.customer_birthday,
						T2.customer_email,
						T2.customer_money,
						T2.platform_money,
						T2.count_order,
						T2.avg_price_order,
						T2.median_time_order_completed,
						first_value(T3.product_type) over(partition by T2.customer_id order by T3.count_product desc) as top_product_category,
						first_value(T5.craftsman_id) over(partition by T2.customer_id order by T5.count_orders desc) as top_craftsman_id,
						T2.count_order_created,
						T2.count_order_in_progress,
						T2.count_order_delivery,
						T2.count_order_done,
						T2.count_order_not_done,
						T2.report_period
						FROM (
							SELECT
								T1.customer_id AS customer_id,
								T1.customer_name AS customer_name,
								T1.customer_address AS customer_address,
								T1.customer_birthday AS customer_birthday,
								T1.customer_email AS customer_email,
								SUM(T1.product_price) as customer_money,
								SUM(T1.product_price) * 0.1 as platform_money,
								count(T1.order_id) AS count_order,
								avg(T1.product_price) AS avg_price_order,
								percentile_cont(0.5) WITHIN GROUP(ORDER BY T1.diff_order_date) AS median_time_order_completed,
								sum(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created,
								sum(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END)AS count_order_in_progress,
								sum(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END)AS count_order_delivery,
								sum(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END)AS count_order_done,
								sum(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END)AS count_order_not_done,
								T1.report_period AS report_period
								FROM (
									SELECT
											dcs.customer_id AS customer_id,
											dcs.customer_name AS customer_name,
											dcs.customer_address AS customer_address,
											dcs.customer_birthday AS customer_birthday,
											dcs.customer_email AS customer_email,
											fo.order_id AS order_id,
											dp.product_id AS product_id,
											dp.product_price AS product_price,
											dp.product_type AS product_type,
											fo.order_completion_date - fo.order_created_date AS diff_order_date,
											fo.order_status AS order_status, 
											to_char(fo.order_created_date, 'yyyy-mm') AS report_period
											FROM dwh.f_order fo 
												INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
												INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
												INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id
												INNER JOIN dwh.dwh_update_delta ud ON fo.customer_id = ud.customer_id
								) AS T1
									GROUP BY T1.customer_id, T1.customer_name, T1.customer_address, T1.customer_birthday, T1.customer_email,T1.report_period-- напишите код здесь
							) AS T2 
								INNER JOIN (
									SELECT
											dd.customer_id as customer_id_for_product_type,
											dd.product_type,
											COUNT(dd.product_id) AS count_product
											FROM dwh.dwh_delta AS dd
												GROUP BY dd.customer_id, dd.product_type
													ORDER BY count_product DESC) AS T3 ON T2.customer_id = T3.customer_id_for_product_type
								INNER JOIN (
									SELECT
											dd.customer_id as customer_id_for_top_craftsman,
											dd.craftsman_id,
											COUNT(dd.order_id) AS count_orders
											FROM dwh.dwh_delta AS dd
												GROUP BY dd.customer_id, dd.craftsman_id
													ORDER BY count_orders DESC) AS T5 ON T2.customer_id = T5.customer_id_for_top_craftsman
),
insert_delta AS ( -- + 
    INSERT INTO dwh.customer_report_datamart (
        customer_id,
        customer_name,
        customer_address,
        customer_birthday, 
        customer_email, 
        customer_money, 
        platform_money, 
        count_order, 
        avg_price_order, 
        median_time_order_completed,
        top_product_category, 
        top_craftsman_id,
        count_order_created, 
        count_order_in_progress, 
        count_order_delivery, 
        count_order_done, 
        count_order_not_done, 
        report_period
    ) SELECT 
            customer_id,
            customer_name,
            customer_address,
            customer_birthday,
            customer_email,
            customer_money,
            platform_money,
            count_order,
            avg_price_order,
            median_time_order_completed,
            top_product_category,
        	top_craftsman_id,
            count_order_created, 
            count_order_in_progress,
            count_order_delivery, 
            count_order_done, 
            count_order_not_done,
            report_period 
            FROM dwh_delta_insert_result
),
update_delta AS ( -- +
    UPDATE dwh.customer_report_datamart SET
        customer_name = updates.customer_name, 
        customer_address = updates.customer_address, 
        customer_birthday = updates.customer_birthday, 
        customer_email = updates.customer_email, 
        customer_money = updates.customer_money, 
        platform_money = updates.platform_money, 
        count_order = updates.count_order, 
        avg_price_order = updates.avg_price_order, 
        median_time_order_completed = updates.median_time_order_completed, 
        top_product_category = updates.top_product_category,
        top_craftsman_id = updates.top_craftsman_id,
        count_order_created = updates.count_order_created, 
        count_order_in_progress = updates.count_order_in_progress, 
        count_order_delivery = updates.count_order_delivery, 
        count_order_done = updates.count_order_done,
        count_order_not_done = updates.count_order_not_done, 
        report_period = updates.report_period
    FROM (
        SELECT 
            customer_id,
            customer_name,
            customer_address,
            customer_birthday,
            customer_email,
            customer_money,
            platform_money,
            count_order,
            avg_price_order,
            median_time_order_completed,
            top_product_category,
            top_craftsman_id,
            count_order_created,
            count_order_in_progress,
            count_order_delivery,
            count_order_done,
            count_order_not_done,
            report_period 
            FROM dwh_delta_update_result) AS updates
    WHERE dwh.customer_report_datamart.customer_id = updates.customer_id
),
insert_load_date AS ( -- +
    INSERT INTO dwh.load_dates_customer_report_datamart (
        load_dttm
    )
    SELECT GREATEST(COALESCE(MAX(craftsman_load_dttm), NOW()), 
                    COALESCE(MAX(customers_load_dttm), NOW()), 
                    COALESCE(MAX(products_load_dttm), NOW())) 
        FROM dwh_delta
)
SELECT 'increment customer_datamart';