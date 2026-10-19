class Account:
    def __init__(self, balance):
        self._balance = balance

    @property
    def balance(self):
        return self._balance

    @staticmethod
    def validate(amount):
        return amount > 0