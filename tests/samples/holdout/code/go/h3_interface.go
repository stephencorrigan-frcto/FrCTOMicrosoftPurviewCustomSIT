type PriceSource interface {
	Latest(symbol string) (float64, error)
}