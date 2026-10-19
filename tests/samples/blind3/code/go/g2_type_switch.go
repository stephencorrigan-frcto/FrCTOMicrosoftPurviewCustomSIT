switch v := msg.(type) {
case Trade:
	handleTrade(v)
case Quote:
	handleQuote(v)
}