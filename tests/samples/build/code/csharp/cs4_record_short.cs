public record Trade(string Symbol, int Qty, decimal Price);
public interface ITradeStore { Task SaveAsync(Trade t); }