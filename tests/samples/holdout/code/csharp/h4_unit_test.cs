[Fact]
public void Total_IsZero_WhenEmpty()
{
    var book = new TradeBook();
    Assert.Equal(0m, book.Total());
}