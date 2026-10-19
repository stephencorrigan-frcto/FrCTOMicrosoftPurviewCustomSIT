enum Side { Buy = "BUY", Sell = "SELL" }
const sideLabel = (s: Side): string => (s === Side.Buy ? "Buy" : "Sell");