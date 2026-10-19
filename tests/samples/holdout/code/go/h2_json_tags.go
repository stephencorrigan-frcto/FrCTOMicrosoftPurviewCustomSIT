type Trade struct {
	Symbol string  `json:"symbol"`
	Qty    int     `json:"qty"`
	Price  float64 `json:"price"`
}