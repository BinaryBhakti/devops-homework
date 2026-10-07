"""Pure calculator logic — no Flask here, so it is trivially unit-testable."""

OPERATIONS = ("add", "subtract", "multiply", "divide")


def add(a: float, b: float) -> float:
    return a + b


def subtract(a: float, b: float) -> float:
    return a - b


def multiply(a: float, b: float) -> float:
    return a * b


def divide(a: float, b: float) -> float:
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b


def calculate(op: str, a: float, b: float) -> float:
    funcs = {"add": add, "subtract": subtract, "multiply": multiply, "divide": divide}
    if op not in funcs:
        raise ValueError(f"Unknown operation '{op}'. Use one of: {', '.join(OPERATIONS)}")
    return funcs[op](a, b)
