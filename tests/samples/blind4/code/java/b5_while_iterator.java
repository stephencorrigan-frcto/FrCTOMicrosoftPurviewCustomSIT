Iterator<Trade> it = trades.iterator();
while (it.hasNext()) {
    if (it.next().isCancelled()) it.remove();
}