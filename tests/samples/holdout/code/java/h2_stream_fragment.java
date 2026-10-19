List<String> symbols = trades.stream()
    .filter(t -> t.getQty() > 0)
    .map(Trade::getSymbol)
    .collect(Collectors.toList());