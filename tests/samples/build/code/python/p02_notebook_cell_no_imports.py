df = df[df["qty"] > 0]
df["notional"] = df["qty"] * df["price"]
df.head()