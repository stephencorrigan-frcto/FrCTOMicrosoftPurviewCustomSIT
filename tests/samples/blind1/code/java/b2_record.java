public record Quote(String symbol, double bid, double ask) {
    public double mid() { return (bid + ask) / 2; }
}