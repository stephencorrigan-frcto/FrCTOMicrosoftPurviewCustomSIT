def apply_all(funcs, value):
    for f in funcs:
        value = f(value)
    return value

double = lambda x: x * 2
print(apply_all([double, double], 3))