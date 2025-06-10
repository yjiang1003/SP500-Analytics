import mysql.connector
import pandas as pd
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt
from sqlalchemy import create_engine
import numpy as np
# Create a SQLAlchemy engine
engine = create_engine(
    "mysql+mysqlconnector://root:abc1234@127.0.0.1:3306/Stock Data"
)
# Use pandas with SQLAlchemy
df = pd.read_sql("""
    SELECT observation_date,
           closePrice
    FROM SP500
    ORDER BY observation_date
""", con=engine, parse_dates=["observation_date"])

#------------------------------------------------------------------
# Plot SP500 Close Price Over Time
plt.figure(figsize=(10, 6))
plt.plot(df.observation_date, df.closePrice)
plt.title("S&P 500 Close Price Over Time")
plt.xlabel("Date")
plt.ylabel("Close Price")
plt.tight_layout()
plt.show()

#------------------------------------------------------------------
# Plot SP500 Daily Return
df["daily_ret"] = df.closePrice.pct_change() * 100
plt.figure(figsize=(10,4))
plt.plot(df.observation_date, df.daily_ret, linewidth=0.8, alpha=0.7)
plt.title("S&P 500 Daily Return (%)")
plt.ylabel("Daily % Return")
plt.xlabel("Date")
plt.tight_layout()
plt.show()

#------------------------------------------------------------------
# 30 Day Rolling Volatility
df_vol = pd.read_sql(
    """
    SELECT 
      observation_date, 
      ann_volatility 
    FROM sp500_rolling_vol
    WHERE ann_volatility IS NOT NULL
    ORDER BY observation_date
    """,
    con=engine,
    parse_dates=["observation_date"]
)
engine.dispose()

plt.figure(figsize=(10, 4))
plt.plot(
    df_vol.observation_date,
    df_vol.ann_volatility * 100,  
    linewidth=1
)
plt.title("S&P 500 30-Day Rolling Volatility (Annualized %)")
plt.xlabel("Date")
plt.ylabel("Annualized Volatility (%)")
plt.tight_layout()
plt.show()

#------------------------------------------------------------------
# Moving Avg & Bollinger Bands
# If dtype is object (strings) or there are nulls, coerce/fill
df["closePrice"] = pd.to_numeric(df["closePrice"], errors="coerce")
# Forward-fill any missing prices
df["closePrice"].ffill(inplace=True)

df["ma50"] = df.closePrice.rolling(window=50).mean()
df["ma200"] = df.closePrice.rolling(window=200).mean()
std50 = df.closePrice.rolling(window=50).std()
df["bb_upper"] = df.ma50 + 2 * std50
df["bb_lower"] = df.ma50 - 2 * std50

fig, ax = plt.subplots(figsize=(12,6))
ax.fill_between(
    df.observation_date,
    df.bb_lower,
    df.bb_upper,
    color="lightgray",
    alpha=0.5,
    label="Bollinger Bands (±2σ)",
    zorder=0
)
ax.plot(
    df.observation_date,
    df.closePrice,
    label="Close Price",
    linewidth=1,
    zorder=1
)
ax.plot(
    df.observation_date,
    df.ma50,
    label="50-Day MA",
    linewidth=1.5,
    zorder=2
)
valid = df.ma200.notna()
ax.plot(
    df.observation_date[valid],
    df.ma200[valid],
    label="200-Day MA",
    linewidth=2,
    color="green",
    zorder=3
)
ax.set_title("S&P 500: Price with 50/200-Day MAs & Bollinger Bands")
ax.set_xlabel("Date")
ax.set_ylabel("Price")
ax.legend()
fig.autofmt_xdate()
plt.tight_layout()
plt.show()

#------------------------------------------------------------------
# Drawdown Curve
df["cum_max"]   = df.closePrice.cummax()
df["drawdown"]  = (df.closePrice / df.cum_max - 1) * 100

plt.figure(figsize=(10,4))
plt.fill_between(df.observation_date, df.drawdown, 0, color="red", alpha=0.3)
plt.title("Drawdown (%) from All-Time High")
plt.ylabel("Drawdown %")
plt.xlabel("Date")
plt.tight_layout()
plt.show()

#------------------------------------------------------------------
# Monthly and Yearly Bar Charts
# Pull in monthly‐returns view
monthly = pd.read_sql("""
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
  ROUND((last_close - prev_month_close) * 100 / prev_month_close, 2) 
    AS monthly_return_pct
FROM monthly_with_prev
WHERE prev_month_close IS NOT NULL
ORDER BY yr, mo;
""", con=engine)
# Build a datetime “period” column at the first of each month
monthly["period"] = pd.to_datetime(
    monthly["yr"].astype(str) + "-" +
    monthly["mo"].astype(str).str.zfill(2) + "-01"
)
fig, ax = plt.subplots(figsize=(12, 4))
ax.bar(
    monthly["period"],
    monthly["monthly_return_pct"],
    width=20
)

ax.set_title("S&P 500 Month-over-Month Return %")
ax.set_xlabel("Month")
ax.set_ylabel("Return %")

# format x-axis to show Year-Month
ax.xaxis.set_major_formatter(
    plt.matplotlib.dates.DateFormatter("%Y-%m")
)
plt.xticks(rotation=45)
plt.tight_layout()
plt.show()

#------------------------------------------------------------------
# Pull in yearly‐returns view
yearly = pd.read_sql(
    """
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
    """,
    con=engine
)
yearly["yr"] = yearly["yr"].astype(int)
# Plot bar chart
fig, ax = plt.subplots(figsize=(8,4))
ax.bar(yearly["yr"].astype(str), yearly["yearly_return_pct"], width=0.6)
ax.set_title("S&P 500 Year-over-Year Return %")
ax.set_xlabel("Year")
ax.set_ylabel("Return %")
plt.xticks(rotation=45)
plt.tight_layout()
plt.show()

# ------------------------------------------------------------------
# Plot Full Equity Curves
df = pd.read_sql("""
  SELECT 
    b.observation_date,
    b.bnh_equity,
    t.equity_value AS strategy_equity
  FROM sp500_buy_and_hold AS b
  JOIN sp500_backtest    AS t
    ON b.observation_date = t.observation_date
  ORDER BY b.observation_date
""", con=engine, parse_dates=["observation_date"])

plt.figure(figsize=(12,6))
plt.plot(df.observation_date, df.bnh_equity,       label="Buy & Hold")
plt.plot(df.observation_date, df.strategy_equity,  label="MA Crossover Strategy")
plt.title("Equity Curves: Strategy vs. Buy & Hold")
plt.xlabel("Date")
plt.ylabel("Equity Value ($)")
plt.legend()
plt.tight_layout()
plt.show()


engine.dispose()
