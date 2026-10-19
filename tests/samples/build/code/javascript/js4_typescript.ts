export interface Trade {
  symbol: string;
  qty: number;
}
export const notional = (t: Trade, price: number): number => t.qty * price;