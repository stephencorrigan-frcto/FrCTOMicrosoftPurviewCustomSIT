import pandas as pd

# 1. Create a sample time series (daily data)
dates = pd.date_range(start="2026-01-01", periods=5, freq="D")
values = [10.5, 12.0, 11.5, 13.0, 12.5]
ts = pd.Series(values, index=dates)

# 2. Calculate mean and standard deviation
mean = ts.mean()
std = ts.std()
print(f"Mean: {mean:.2f}  Std: {std:.2f}")