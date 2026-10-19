import pandas as pd
df = pd.read_csv("trades.csv")
df["pnl"] = df["price"] * df["qty"]
print(df.groupby("symbol")["pnl"].sum())