public interface PriceSource extends AutoCloseable {
    double latest(String symbol) throws IOException;
}