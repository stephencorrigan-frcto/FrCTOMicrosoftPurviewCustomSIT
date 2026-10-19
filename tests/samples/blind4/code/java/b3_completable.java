CompletableFuture.supplyAsync(() -> loadPrices())
    .thenAccept(prices -> cache.putAll(prices));