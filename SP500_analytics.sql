USE `Stock Data`;

-- Verify Data 
SELECT COUNT(*) AS total_rows 
FROM SP500;

SELECT * 
FROM SP500 
ORDER BY observation_date DESC
LIMIT 5;

-- ----------------------------------------------
-- Calculate/View Daily Returns
CREATE OR REPLACE VIEW sp500_daily_ret AS
SELECT
  observation_date,
  closePrice,
  LAG(closePrice) OVER (ORDER BY observation_date) AS prev_close,
  ROUND((closePrice / LAG(closePrice) OVER (ORDER BY observation_date) - 1) * 100, 4) 
    AS daily_pct_return
FROM SP500;

SELECT * 
FROM sp500_daily_ret 
WHERE prev_close IS NOT NULL 
ORDER BY observation_date 
LIMIT 10;

-- ----------------------------------------------
-- Build Moving Avg
CREATE OR REPLACE VIEW sp500_with_ma AS
SELECT
  observation_date,
  closePrice,
  ROUND(
    AVG(closePrice) OVER (
      ORDER BY observation_date 
      ROWS BETWEEN 49 PRECEDING AND CURRENT ROW
    ), 
    2
  ) AS ma_50, -- 50 days
  ROUND(
    AVG(closePrice) OVER (
      ORDER BY observation_date 
      ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
    ), 
    2
  ) AS ma_200 -- 200 days
FROM SP500;

SELECT *
FROM sp500_with_ma
WHERE ma_50 IS NOT NULL 
  AND ma_200 IS NOT NULL
ORDER BY observation_date DESC
LIMIT 10;

-- -----------------------------------------------------
-- Golden Cross (MA50 crossing above MA200)
CREATE OR REPLACE VIEW sp500_cross_signals AS -- compares today’s MAs with yesterday’s
SELECT 
  observation_date,
  closePrice,
  ma_50,
  ma_200,
  LAG(ma_50) OVER (ORDER BY observation_date) AS prev_ma_50,
  LAG(ma_200) OVER (ORDER BY observation_date) AS prev_ma_200
FROM sp500_with_ma;

SELECT -- dates where yesterday MA50 < MA200 and today MA50 ≥ MA200
  observation_date, 
  closePrice, 
  ma_50, 
  ma_200
FROM sp500_cross_signals
WHERE prev_ma_50 < prev_ma_200
  AND ma_50 >= ma_200
ORDER BY observation_date;

-- -----------------------------------------------------
-- 30 day rolling volatility
CREATE OR REPLACE VIEW sp500_rolling_vol AS
WITH daily_ret AS (
  SELECT
    observation_date,
    (closePrice / LAG(closePrice) OVER (ORDER BY observation_date) - 1) AS ret
  FROM SP500
)
SELECT
  observation_date,
  ROUND(
    STDDEV_POP(ret) OVER (
      ORDER BY observation_date 
      ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) * SQRT(252),
    4
  ) AS ann_volatility
FROM daily_ret
WHERE ret IS NOT NULL;

SELECT * 
FROM sp500_rolling_vol
WHERE ann_volatility IS NOT NULL
ORDER BY observation_date
LIMIT 10;

-- --------------------------------------------------
-- Max Drawdown
CREATE OR REPLACE VIEW sp500_drawdown AS
SELECT 
  observation_date,
  closePrice,
  MAX(closePrice) OVER (ORDER BY observation_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) 
    AS running_peak,
  ROUND(
    (closePrice / MAX(closePrice) OVER (ORDER BY observation_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) - 1) * 100,
    4
  ) AS drawdown_pct
FROM SP500;

SELECT observation_date, closePrice, running_peak, drawdown_pct -- find worst drawdown
FROM sp500_drawdown
WHERE drawdown_pct = (SELECT MIN(drawdown_pct) FROM sp500_drawdown);

-- ----------------------------------------------------------
-- Aggregate Monthly & Yearly Returns
-- Monthy
WITH monthly_bounds AS (
  SELECT
    YEAR(observation_date)  AS yr,
    MONTH(observation_date) AS mo,
    MIN(observation_date)   AS first_date,
    MAX(observation_date)   AS last_date
  FROM SP500
  GROUP BY YEAR(observation_date), MONTH(observation_date)
),
monthly_prices AS (
  SELECT
    mb.yr,
    mb.mo,
    s1.closePrice AS first_close,
    s2.closePrice AS last_close
  FROM monthly_bounds mb
  JOIN SP500 s1 ON s1.observation_date = mb.first_date
  JOIN SP500 s2 ON s2.observation_date = mb.last_date
),
monthly_with_prev AS (
  SELECT
    yr,
    mo,
    first_close,
    last_close,
    LAG(last_close) OVER (ORDER BY yr, mo) AS prev_month_close
  FROM monthly_prices
)
SELECT
  yr,
  mo,
  ROUND(
    (last_close - prev_month_close) * 100
    / prev_month_close,
    2
  ) AS monthly_return_pct
FROM monthly_with_prev
WHERE prev_month_close IS NOT NULL
ORDER BY yr, mo;

-- Yearly
WITH yearly_bounds AS (
  SELECT
    YEAR(observation_date) AS yr,
    MIN(observation_date)   AS first_date,
    MAX(observation_date)   AS last_date
  FROM SP500
  GROUP BY YEAR(observation_date)
),
yearly_prices AS (
  SELECT
    yb.yr,
    s1.closePrice AS first_close,
    s2.closePrice AS last_close
  FROM yearly_bounds yb
  JOIN SP500 s1 ON s1.observation_date = yb.first_date
  JOIN SP500 s2 ON s2.observation_date = yb.last_date
),
yearly_with_prev AS (
  SELECT
    yr,
    first_close,
    last_close,
    LAG(last_close) OVER (ORDER BY yr) AS prev_year_close
  FROM yearly_prices
)
SELECT
  yr,
  ROUND(
    (last_close - prev_year_close) * 100
    / prev_year_close,
    2
  ) AS yearly_return_pct
FROM yearly_with_prev
WHERE prev_year_close IS NOT NULL
ORDER BY yr;

-- ------------------------------------------------------
-- Average Daily Return by Month
CREATE OR REPLACE VIEW sp500_avg_return_by_month AS
WITH daily_ret AS (
  SELECT 
    observation_date,
    (closePrice / LAG(closePrice) OVER (ORDER BY observation_date) - 1) AS ret
  FROM SP500
)
SELECT
  MONTH(observation_date) AS month_num,
  ROUND(AVG(ret) * 100, 4) AS avg_daily_return_pct
FROM daily_ret
WHERE ret IS NOT NULL
GROUP BY month_num
ORDER BY month_num;
SELECT * FROM sp500_avg_return_by_month;

-- -------------------------------------------------------
-- Average Daily Return by Day of Week
CREATE OR REPLACE VIEW sp500_avg_return_by_weekday AS
WITH daily_ret AS (
  SELECT 
    observation_date,
    DAYOFWEEK(observation_date) AS dow,
    (closePrice / LAG(closePrice) OVER (ORDER BY observation_date) - 1) AS ret
  FROM SP500
)
SELECT
  dow,
  CASE dow
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END AS weekday_name,
  ROUND(AVG(ret) * 100, 4) AS avg_daily_return_pct
FROM daily_ret
WHERE ret IS NOT NULL 
  AND dow BETWEEN 1 AND 7   
GROUP BY dow
ORDER BY dow;
SELECT * FROM sp500_avg_return_by_weekday;

-- --------------------------------------------------
-- Create a view that assigns a "long" flag
CREATE OR REPLACE VIEW sp500_signal AS
SELECT
  observation_date,
  closePrice,
  CASE 
    WHEN ma_50 > ma_200 THEN 1 
    ELSE 0 
  END AS long_flag
FROM sp500_with_ma
WHERE ma_50 IS NOT NULL 
  AND ma_200 IS NOT NULL;

-- Compute Daily Return and Equity Growth
CREATE OR REPLACE VIEW sp500_backtest AS
WITH ranked AS (
  SELECT
    observation_date,
    closePrice,
    long_flag,
    (closePrice / LAG(closePrice) OVER (ORDER BY observation_date) - 1) AS daily_ret
  FROM sp500_signal
)
SELECT
  observation_date,
  closePrice,
  long_flag,
  ROUND(
    EXP(
      SUM(
        LOG(1 + IF(long_flag = 1, daily_ret, 0))
      ) OVER (ORDER BY observation_date)
    ) * 10000, 2
  ) AS equity_value
FROM ranked
WHERE daily_ret IS NOT NULL
ORDER BY observation_date;

-- Compare to buy and hold
CREATE OR REPLACE VIEW sp500_buy_and_hold AS
WITH daily_ret AS (
  SELECT
    observation_date,
    (closePrice / LAG(closePrice) OVER (ORDER BY observation_date) - 1) AS daily_ret
  FROM SP500
)
SELECT
  observation_date,
  ROUND(
    EXP(
      SUM(LOG(1 + daily_ret)) 
      OVER (ORDER BY observation_date)
    ) * 10000, 2
  ) AS bnh_equity
FROM daily_ret
WHERE daily_ret IS NOT NULL
ORDER BY observation_date;

-- Compare equity curves by date
SELECT 
  b.observation_date,
  b.bnh_equity,
  t.equity_value AS strategy_equity
FROM sp500_buy_and_hold AS b
JOIN sp500_backtest AS t
  ON b.observation_date = t.observation_date
ORDER BY b.observation_date
LIMIT 10;