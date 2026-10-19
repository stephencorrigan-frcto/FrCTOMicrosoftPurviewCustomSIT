class Pricer:
    def __init__(self, rate: float) -> None:
        self.rate = rate

    def discount(self, price: float, years: int) -> float:
        return price / (1 + self.rate) ** years