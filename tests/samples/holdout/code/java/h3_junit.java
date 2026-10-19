@Test
void totalIsZeroWhenEmpty() {
    PriceBook book = new PriceBook();
    assertEquals(0.0, book.total(), 0.0001);
}