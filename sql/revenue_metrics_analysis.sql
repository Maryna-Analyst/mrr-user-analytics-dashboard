-- REVENUE METRICS

-- ПЕРЕВІРКА ЯКОСТІ ДАНИХ:
-- Перевірка порожніх значень:
SELECT
    COUNT(*) AS total_rows,
    COUNT(user_id) AS user_id_cnt,
    COUNT(game_name) AS game_name_cnt,
    COUNT(payment_date) AS payment_date_cnt,
    COUNT(revenue_amount_usd) AS revenue_cnt
FROM project.games_payments;

-- Перевірка дублікатів:
SELECT
    user_id,
    game_name,
    payment_date,
    revenue_amount_usd,
    COUNT(*)
FROM project.games_payments
GROUP BY
    user_id,
    game_name,
    payment_date,
    revenue_amount_usd
HAVING COUNT(*) > 1;

-- Чи є від'ємний або нульовий дохід
SELECT *
FROM project.games_payments
WHERE revenue_amount_usd <= 0;


-- Діапазон дат
SELECT
    MIN(payment_date),
    MAX(payment_date)
FROM project.games_payments;   


-- Чи може один користувач платити за кілька різних ігор:
SELECT
    user_id,
    COUNT(DISTINCT game_name) AS games
FROM project.games_payments
GROUP BY user_id
HAVING COUNT(DISTINCT game_name) > 1;
    

-- При перевірці на дублікати було виявлено один дублікат. Було прийнято рішення видалити його: 
WITH payments AS (
    SELECT DISTINCT
        user_id,
        payment_date,
        revenue_amount_usd
    FROM project.games_payments
),
--Розраховуємо revenue користувача за кожен місяць:
monthly_user_revenue as (
select DATE_TRUNC('month', payment_date)::date AS payment_month,
	user_id,
	sum(revenue_amount_usd) as monthly_revenue 
from payments
group by payment_month, user_id
),
-- Розраховуємо додаткові поля, які знадобляться для розрахунку метрик
user_payment_history as ( 
select payment_month,
	user_id,
	monthly_revenue,
	lag (monthly_revenue) over (PARTITION BY user_id ORDER BY payment_month) as previous_month_revenue,
	lead(payment_month) over (PARTITION BY user_id ORDER BY payment_month) as next_payment_month,
	lag(payment_month) over (PARTITION BY user_id ORDER BY payment_month) AS previous_payment_month,
	date(payment_month + interval '1 month') as next_calendar_month,
	date(payment_month - interval '1 month') as previous_calendar_month
from monthly_user_revenue
),
user_metrics as (
select *,
	CASE
	    WHEN previous_payment_month = previous_calendar_month
	     AND monthly_revenue > previous_month_revenue
	    THEN monthly_revenue - previous_month_revenue
	    ELSE 0
	END AS expansion_mrr,
	CASE
	    WHEN previous_payment_month = previous_calendar_month
	     AND monthly_revenue < previous_month_revenue
	    THEN monthly_revenue - previous_month_revenue
	    ELSE 0
	END AS contraction_mrr
from user_payment_history
)
select  user_metrics.*,
	case
		when previous_month_revenue is null then 'new'
		when previous_payment_month = previous_calendar_month  then 'retained'
		when previous_payment_month < previous_calendar_month then 'back from churn'
		else 'error'
	end as status,
	case 
		when next_payment_month is null or next_payment_month != next_calendar_month 
		then true else false 
	end as is_churn,
	gpu.language,
	gpu.has_older_device_model,
	gpu.age,
	gpu.game_name
from user_metrics 
left join project.games_paid_users gpu on gpu.user_id = user_metrics.user_id;
