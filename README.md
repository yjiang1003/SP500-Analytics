# SP500-Analytics Project
## Overview
This end-to-end analytics project ingests five years of daily S&P 500 closing prices into a relational database, builds a suite of SQL views for core time-series computations, and then uses Python (pandas + Matplotlib) to visualize insights, test a simple moving-average crossover strategy, and compare it against buy-and-hold.

- Data Source: Daily closing levels from FRED (S&P 500). https://fred.stlouisfed.org/series/SP500
  - Data used for this porject ranges from 6/6/20 to 6/6/25
- Data Structure
  - closePrice
  - observation_date
- Database: MySQL, with window functions and CTEs for time-series metrics.
- Analysis & Visualization: Python (pandas, Matplotlib, mysql-connector-python)

