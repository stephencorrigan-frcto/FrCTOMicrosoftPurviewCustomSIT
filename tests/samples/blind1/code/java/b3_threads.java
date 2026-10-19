ExecutorService pool = Executors.newFixedThreadPool(4);
pool.submit(() -> refreshPrices());
pool.shutdown();