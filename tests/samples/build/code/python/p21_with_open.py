with open("positions.csv") as f:
    for line in f:
        symbol, qty = line.strip().split(",")
        print(symbol, qty)