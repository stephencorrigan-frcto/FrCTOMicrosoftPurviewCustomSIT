def clean_prices(rows):
    out = []
    for row in rows:
        if row["price"] is None:
            continue
        out.append(round(float(row["price"]), 2))
    return out