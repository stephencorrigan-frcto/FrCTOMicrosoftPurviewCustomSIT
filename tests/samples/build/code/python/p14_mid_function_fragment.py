    results = []
    for row in rows:
        if row["qty"] > 0:
            results.append(row["price"] * row["qty"])
    total = sum(results)
    return total