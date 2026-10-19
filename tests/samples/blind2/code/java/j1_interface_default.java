public interface Pricer {
    double price(String symbol);
    default double spread(String s) { return price(s) * 0.001; }
}