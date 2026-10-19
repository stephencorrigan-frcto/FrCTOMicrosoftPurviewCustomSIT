Optional<Trade> first = trades.stream().filter(Trade::isOpen).findFirst();
first.ifPresent(t -> log.info("open trade {}", t.getId()));