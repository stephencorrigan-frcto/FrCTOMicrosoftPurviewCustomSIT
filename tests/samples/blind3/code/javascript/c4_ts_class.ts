export class PriceFeed {
  private subs: Array<(p: number) => void> = [];
  subscribe(fn: (p: number) => void) { this.subs.push(fn); }
}