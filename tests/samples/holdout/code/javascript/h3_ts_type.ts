type Side = "buy" | "sell";
export async function placeOrder(symbol: string, side: Side): Promise<void> {
  await api.post("/orders", { symbol, side });
}