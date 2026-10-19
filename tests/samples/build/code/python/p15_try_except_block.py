try:
    value = int(raw_input)
except ValueError as e:
    print("bad value", e)
    value = None