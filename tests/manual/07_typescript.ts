export interface Trade {
  symbol: string;
  qty: number;
}
export const notional = (t: Trade, price: number): number => t.qty * price;
console.log(notional({ symbol: "TEST", qty: 10 }, 2.5));